#!/usr/bin/env node
/**
 * add_assets_to_xcode.js
 * ----------------------
 * Registers image assets (PNG) from a folder into an Xcode project file
 * (project.pbxproj) without opening Xcode.
 *
 * What it does:
 *   1. Finds all PNG files in the given assets directory
 *   2. Adds a PBXFileReference for each file
 *   3. Adds a PBXBuildFile for each file (marks it for Copy Bundle Resources)
 *   4. Adds each file to the Resources build phase of the target
 *   5. Creates a named PBXGroup in the project navigator and adds files to it
 *
 * Idempotent: files already referenced in the project are silently skipped.
 * Deterministic: UUIDs are derived from filenames so repeated runs produce
 * the same IDs and never create duplicates.
 *
 * Usage:
 *   node add_assets_to_xcode.js \
 *     --project  Glimpse/Glimpse.xcodeproj/project.pbxproj \
 *     --assets   Glimpse/public/layers/Tahoe \
 *     --group    "Layers/Tahoe"
 *
 * Arguments:
 *   --project   Path to project.pbxproj (required)
 *   --assets    Directory containing PNG files to register (required)
 *   --group     Navigator group name shown in Xcode (default: folder name)
 *   --target    Resources build phase ID to add files to (default: auto-detect)
 *
 * Requirements:
 *   npm install minimist   (sharp not required for this script)
 */

const fs       = require('fs');
const path     = require('path');
const crypto   = require('crypto');
const minimist = require('minimist');

// ---------------------------------------------------------------------------
// UUID helpers — deterministic 24-char hex IDs (Xcode-compatible format)
// ---------------------------------------------------------------------------

/**
 * Generate a deterministic 24-char uppercase hex ID from a seed string.
 * Using MD5 purely as a hash (not for security), capped to 24 chars.
 */
function makeId(seed) {
  return crypto.createHash('md5').update(seed).digest('hex').slice(0, 24).toUpperCase();
}

// ---------------------------------------------------------------------------
// pbxproj manipulation helpers
// ---------------------------------------------------------------------------

/**
 * Insert `lines` before the first occurrence of `marker` in `content`.
 */
function insertBefore(content, marker, lines) {
  const idx = content.indexOf(marker);
  if (idx === -1) throw new Error(`Marker not found: ${marker}`);
  return content.slice(0, idx) + lines + '\n' + content.slice(idx);
}

/**
 * Insert `entry` into the files/children list of a specific PBX section block.
 * Finds the block starting with `blockId`, then inserts inside its `listKey` list.
 *
 * @param {string} content     Full pbxproj string
 * @param {string} blockId     The PBX object ID of the block (e.g. 'A7000002')
 * @param {string} listKey     The key whose list to append to ('files' | 'children')
 * @param {string} entry       The line to insert (without trailing newline)
 * @returns {string}           Modified content
 */
function insertIntoList(content, blockId, listKey, entry) {
  // Find the block by its ID
  const blockStart = content.indexOf(blockId);
  if (blockStart === -1) throw new Error(`Block not found: ${blockId}`);

  // Find the listKey inside the block
  const listKeyPos = content.indexOf(`${listKey} = (`, blockStart);
  if (listKeyPos === -1) throw new Error(`"${listKey}" list not found in block ${blockId}`);

  // Find the closing ); of this list
  const listOpen  = content.indexOf('(', listKeyPos) + 1;
  const listClose = content.indexOf('\t\t\t);', listOpen);  // closing paren at 3-tab indent

  const existing = content.slice(listOpen, listClose);
  const separator = existing.trim() ? '' : '';  // always add on its own line
  const indent = '\t\t\t\t';

  return (
    content.slice(0, listClose) +
    (existing.trimEnd().endsWith(',') || !existing.trim() ? '' : '') +
    `${indent}${entry},\n` +
    content.slice(listClose)
  );
}

/**
 * Check whether a PBX block with `blockId` already has `entry` in a list.
 */
function listContains(content, blockId, entry) {
  const blockStart = content.indexOf(blockId);
  if (blockStart === -1) return false;
  // Find the end of this block (closing };)
  const blockEnd = content.indexOf('\n\t\t};', blockStart);
  return content.slice(blockStart, blockEnd).includes(entry);
}

// ---------------------------------------------------------------------------
// Core logic
// ---------------------------------------------------------------------------

function main() {
  const args = minimist(process.argv.slice(2), {
    string:  ['project', 'assets', 'group', 'target'],
    boolean: ['help', 'dry-run'],
    alias:   { h: 'help', n: 'dry-run' },
  });

  if (args.help || !args.project || !args.assets) {
    console.log(`
Usage:
  node add_assets_to_xcode.js --project <pbxproj> --assets <dir> [options]

Options:
  --project   Path to project.pbxproj (required)
  --assets    Directory containing PNG files (required)
  --group     Group name in Xcode navigator (default: directory name)
  --dry-run   Print changes without writing the file
    `);
    process.exit(args.help ? 0 : 1);
  }

  const pbxprojPath  = path.resolve(args.project);
  const assetsDir    = path.resolve(args.assets);
  const groupName    = args.group || path.basename(assetsDir);

  // Project root = directory containing the .xcodeproj bundle
  const projectRoot  = path.dirname(path.dirname(pbxprojPath));
  // Path of assets relative to project root (used as 'path' in PBXGroup)
  const groupRelPath = path.relative(projectRoot, assetsDir);

  if (!fs.existsSync(pbxprojPath)) {
    console.error(`project.pbxproj not found: ${pbxprojPath}`);
    process.exit(1);
  }
  if (!fs.existsSync(assetsDir)) {
    console.error(`Assets directory not found: ${assetsDir}`);
    process.exit(1);
  }

  const pngFiles = fs.readdirSync(assetsDir)
    .filter(f => f.toLowerCase().endsWith('.png'))
    .sort();

  if (pngFiles.length === 0) {
    console.log('No PNG files found in assets directory.');
    return;
  }

  console.log(`\nadd_assets_to_xcode`);
  console.log(`  project   : ${pbxprojPath}`);
  console.log(`  assets    : ${assetsDir}`);
  console.log(`  group     : ${groupName}`);
  console.log(`  files     : ${pngFiles.length} PNGs found`);
  console.log();

  let content = fs.readFileSync(pbxprojPath, 'utf8');

  // Determine which files need to be added (idempotency check)
  const toAdd = pngFiles.filter(filename => {
    if (content.includes(`path = "${filename}"`)) {
      console.log(`  skip (already in project): ${filename}`);
      return false;
    }
    return true;
  });

  if (toAdd.length === 0) {
    console.log('\nAll files already registered. Nothing to do.');
    return;
  }

  // Generate IDs for all new files
  const entries = toAdd.map(filename => ({
    filename,
    fileRefId:   makeId(`fileref:${groupRelPath}:${filename}`),
    buildFileId: makeId(`buildfile:${groupRelPath}:${filename}`),
  }));

  // ---- 1. PBXFileReference entries ----------------------------------------
  const fileRefLines = entries.map(({ fileRefId, filename }) =>
    `\t\t${fileRefId} /* ${filename} */ = {isa = PBXFileReference; lastKnownFileType = image.png; path = "${filename}"; sourceTree = "<group>"; };`
  ).join('\n');

  content = insertBefore(content, '/* End PBXFileReference section */', fileRefLines);
  console.log(`  + ${entries.length} PBXFileReference entries`);

  // ---- 2. PBXBuildFile entries --------------------------------------------
  const buildFileLines = entries.map(({ fileRefId, buildFileId, filename }) =>
    `\t\t${buildFileId} /* ${filename} in Resources */ = {isa = PBXBuildFile; fileRef = ${fileRefId} /* ${filename} */; };`
  ).join('\n');

  content = insertBefore(content, '/* End PBXBuildFile section */', buildFileLines);
  console.log(`  + ${entries.length} PBXBuildFile entries`);

  // ---- 3. PBXGroup for the assets folder ----------------------------------
  const groupId      = makeId(`group:${groupRelPath}`);
  const groupExists  = content.includes(groupId);

  if (!groupExists) {
    // Build group entry with all file refs as children
    const childrenLines = entries.map(({ fileRefId, filename }) =>
      `\t\t\t\t${fileRefId} /* ${filename} */,`
    ).join('\n');

    const groupEntry = [
      `\t\t${groupId} /* ${groupName} */ = {`,
      `\t\t\tisa = PBXGroup;`,
      `\t\t\tchildren = (`,
      childrenLines,
      `\t\t\t);`,
      `\t\t\tname = "${groupName}";`,
      `\t\t\tpath = "${groupRelPath}";`,
      `\t\t\tsourceTree = "<group>";`,
      `\t\t};`,
    ].join('\n');

    content = insertBefore(content, '/* End PBXGroup section */', groupEntry);

    // Add group to root group children (A5000003)
    content = insertIntoList(content, 'A5000003', 'children', `${groupId} /* ${groupName} */`);
    console.log(`  + PBXGroup "${groupName}" created`);
  } else {
    // Group already exists — just add new file refs to its children
    for (const { fileRefId, filename } of entries) {
      if (!listContains(content, groupId, fileRefId)) {
        content = insertIntoList(content, groupId, 'children', `${fileRefId} /* ${filename} */`);
      }
    }
    console.log(`  ~ PBXGroup "${groupName}" already exists — added new children`);
  }

  // ---- 4. Resources build phase (A7000002) --------------------------------
  // Auto-detect the Resources phase ID or use the known one (A7000002)
  const resourcesPhaseId = args.target || 'A7000002';

  for (const { buildFileId, filename } of entries) {
    content = insertIntoList(
      content,
      resourcesPhaseId,
      'files',
      `${buildFileId} /* ${filename} in Resources */`
    );
  }
  console.log(`  + ${entries.length} entries added to Resources build phase`);

  // ---- Write --------------------------------------------------------------
  if (args['dry-run']) {
    console.log('\n[dry-run] No changes written.');
    return;
  }

  // Backup original
  const backupPath = `${pbxprojPath}.bak`;
  fs.copyFileSync(pbxprojPath, backupPath);
  console.log(`\n  Backup saved: ${backupPath}`);

  fs.writeFileSync(pbxprojPath, content, 'utf8');
  console.log(`  Written:      ${pbxprojPath}`);
  console.log(`\nDone. ${toAdd.length} file(s) registered. Reopen Xcode if it was open.`);
}

main();
