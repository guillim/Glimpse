#!/usr/bin/env node
/**
 * depth_layer_slicer.js — v2
 * --------------------------
 * Slices a source image into transparent PNG parallax layers using a depth map.
 *
 * v2 improvements:
 *   - Dense 256-entry Spectral_r LUT with 64³ RGB lookup cube (was 11-point nearest-2)
 *   - Percentile clamping (p2–p98) to use full dynamic range
 *   - Multi-Otsu thresholding for adaptive layer boundaries (was equal-width bins)
 *   - Depth-gradient-aware alpha blending (was hard mask + spatial Gaussian blur)
 *
 * Output naming convention:
 *   {name}_layer_{index:02d}_{z_position}_{label}.png
 *
 * Usage:
 *   node depth_layer_slicer.js \
 *     --image  public/MyPhoto.jpg \
 *     --depth  public/MyPhoto-depth-map.jpg \
 *     --output public/layers/MyPhoto \
 *     --name   myphoto \
 *     --layers 5 \
 *     --transition 8
 *
 * Requirements:
 *   npm install sharp minimist
 */

const sharp    = require('sharp');
const minimist = require('minimist');
const fs       = require('fs');
const path     = require('path');

// ---------------------------------------------------------------------------
// Dense Spectral_r LUT — 256 entries interpolated from matplotlib control points
// ---------------------------------------------------------------------------

const SPECTRAL_R_CONTROL = [
  { d: 0,   r: 94,  g: 79,  b: 162 },
  { d: 26,  r: 50,  g: 136, b: 189 },
  { d: 51,  r: 102, g: 194, b: 165 },
  { d: 77,  r: 171, g: 221, b: 164 },
  { d: 102, r: 230, g: 245, b: 152 },
  { d: 128, r: 255, g: 255, b: 191 },
  { d: 153, r: 254, g: 224, b: 139 },
  { d: 179, r: 253, g: 174, b: 97  },
  { d: 204, r: 244, g: 109, b: 67  },
  { d: 230, r: 213, g: 62,  b: 79  },
  { d: 255, r: 158, g: 1,   b: 66  },
];

function buildDenseLUT() {
  const lut = new Array(256);
  for (let d = 0; d < 256; d++) {
    let lo = 0;
    for (let i = 0; i < SPECTRAL_R_CONTROL.length - 1; i++) {
      if (d >= SPECTRAL_R_CONTROL[i].d && d <= SPECTRAL_R_CONTROL[i + 1].d) {
        lo = i; break;
      }
    }
    const a = SPECTRAL_R_CONTROL[lo], b = SPECTRAL_R_CONTROL[lo + 1];
    const t = a.d === b.d ? 0 : (d - a.d) / (b.d - a.d);
    lut[d] = [
      Math.round(a.r + (b.r - a.r) * t),
      Math.round(a.g + (b.g - a.g) * t),
      Math.round(a.b + (b.b - a.b) * t),
    ];
  }
  return lut;
}

/** Build a 64³ RGB→depth lookup cube for O(1) per-pixel conversion. */
function buildLookupCube(lut, size) {
  const cube = new Uint8Array(size * size * size);
  const scale = 255 / (size - 1);
  for (let ri = 0; ri < size; ri++) {
    const r = ri * scale;
    for (let gi = 0; gi < size; gi++) {
      const g = gi * scale;
      for (let bi = 0; bi < size; bi++) {
        const b = bi * scale;
        let bestDist = Infinity, bestD = 0;
        for (let d = 0; d < 256; d++) {
          const dist = (r - lut[d][0]) ** 2 + (g - lut[d][1]) ** 2 + (b - lut[d][2]) ** 2;
          if (dist < bestDist) { bestDist = dist; bestD = d; }
        }
        cube[ri * size * size + gi * size + bi] = bestD;
      }
    }
  }
  return cube;
}

// ---------------------------------------------------------------------------
// Depth map loading
// ---------------------------------------------------------------------------

function isGrayscale(data, total) {
  let diff = 0;
  const step = Math.max(1, Math.floor(total / 50000));
  let count = 0;
  for (let i = 0; i < total; i += step) {
    diff += Math.abs(data[i * 3] - data[i * 3 + 1]) + Math.abs(data[i * 3] - data[i * 3 + 2]);
    count++;
  }
  return (diff / count) < 10;
}

async function loadDepthAsGrayscale(depthPath, colormap) {
  const { data, info } = await sharp(depthPath)
    .removeAlpha().toColorspace('srgb').raw()
    .toBuffer({ resolveWithObject: true });

  const total = info.width * info.height;
  const forceGray  = colormap === 'grayscale';
  const forceColor = colormap === 'color';

  if (forceGray || (!forceColor && isGrayscale(data, total))) {
    console.log('  Depth map format: grayscale');
    const depth = new Uint8Array(total);
    for (let i = 0; i < total; i++) depth[i] = data[i * 3];
    return { depth, width: info.width, height: info.height };
  }

  console.log('  Depth map format: color-coded (Spectral_r)');
  console.log('  Building dense 256-entry LUT + 64³ lookup cube...');
  const CUBE_SIZE = 64;
  const lut  = buildDenseLUT();
  const cube = buildLookupCube(lut, CUBE_SIZE);
  const scale = (CUBE_SIZE - 1) / 255;

  const depth = new Uint8Array(total);
  for (let i = 0; i < total; i++) {
    const ri = Math.min(CUBE_SIZE - 1, Math.round(data[i * 3]     * scale));
    const gi = Math.min(CUBE_SIZE - 1, Math.round(data[i * 3 + 1] * scale));
    const bi = Math.min(CUBE_SIZE - 1, Math.round(data[i * 3 + 2] * scale));
    depth[i] = cube[ri * CUBE_SIZE * CUBE_SIZE + gi * CUBE_SIZE + bi];
  }

  return { depth, width: info.width, height: info.height };
}

// ---------------------------------------------------------------------------
// Percentile clamping + linear rescale
// ---------------------------------------------------------------------------

function normalizeDepth(depth, total) {
  const hist = new Uint32Array(256);
  for (let i = 0; i < total; i++) hist[depth[i]]++;

  // Find p2 and p98
  const p2Target  = Math.floor(total * 0.02);
  const p98Target = Math.floor(total * 0.98);
  let cumul = 0, pLow = 0, pHigh = 255;
  for (let d = 0; d < 256; d++) {
    cumul += hist[d];
    if (cumul <= p2Target)  pLow = d;
    if (cumul <= p98Target) pHigh = d;
  }
  if (pHigh <= pLow) { pLow = 0; pHigh = 255; }

  console.log(`  Percentile clamp: [${pLow}, ${pHigh}] (p2–p98)`);

  // Clamp and rescale to 0–255
  const range = pHigh - pLow || 1;
  const out = new Uint8Array(total);
  for (let i = 0; i < total; i++) {
    const v = Math.max(pLow, Math.min(pHigh, depth[i]));
    out[i] = Math.round(255 * (v - pLow) / range);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Multi-Otsu thresholding via dynamic programming
//
// Finds 2 thresholds that maximize between-class variance on a 256-bin
// histogram.  O(256²) — trivial.
// ---------------------------------------------------------------------------

function multiOtsuThresholds(depth, total, nClasses) {
  const hist = new Uint32Array(256);
  for (let i = 0; i < total; i++) hist[depth[i]]++;

  // Cumulative count and weighted sum
  const cumH = new Float64Array(256);
  const cumS = new Float64Array(256);
  cumH[0] = hist[0];
  cumS[0] = 0;
  for (let d = 1; d < 256; d++) {
    cumH[d] = cumH[d - 1] + hist[d];
    cumS[d] = cumS[d - 1] + d * hist[d];
  }

  function rangeH(a, b) { return a > 0 ? cumH[b] - cumH[a - 1] : cumH[b]; }
  function rangeS(a, b) { return a > 0 ? cumS[b] - cumS[a - 1] : cumS[b]; }
  function segCost(a, b) {
    const h = rangeH(a, b);
    if (h === 0) return 0;
    const s = rangeS(a, b);
    return (s * s) / h;
  }

  // dp[k][b] = max between-class cost using k segments for bins 0..b
  const dp    = Array.from({ length: nClasses + 1 }, () => new Float64Array(256).fill(-Infinity));
  const split = Array.from({ length: nClasses + 1 }, () => new Int16Array(256).fill(-1));

  // Base: 1 segment covering 0..b
  for (let b = 0; b < 256; b++) dp[1][b] = segCost(0, b);

  // Fill
  for (let k = 2; k <= nClasses; k++) {
    for (let b = k - 1; b < 256; b++) {
      for (let a = k - 1; a <= b; a++) {
        const val = dp[k - 1][a - 1] + segCost(a, b);
        if (val > dp[k][b]) {
          dp[k][b] = val;
          split[k][b] = a;
        }
      }
    }
  }

  // Backtrack to recover segment start positions
  const starts = [];
  let b = 255;
  for (let k = nClasses; k >= 2; k--) {
    starts.unshift(split[k][b]);
    b = split[k][b] - 1;
  }

  // Convert to { low, high } boundaries
  const boundaries = [];
  let lo = 0;
  for (const s of starts) {
    boundaries.push({ low: lo, high: s - 1 });
    lo = s;
  }
  boundaries.push({ low: lo, high: 255 });

  return boundaries;
}

// ---------------------------------------------------------------------------
// Depth gradient (simple 4-neighbour finite differences, normalized to 0–1)
// ---------------------------------------------------------------------------

function computeDepthGradient(depth, width, height) {
  const total = width * height;
  const gradient = new Float32Array(total);
  let maxG = 0;

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = y * width + x;
      const left  = x > 0          ? depth[i - 1]     : depth[i];
      const right = x < width - 1  ? depth[i + 1]     : depth[i];
      const up    = y > 0          ? depth[i - width]  : depth[i];
      const down  = y < height - 1 ? depth[i + width]  : depth[i];
      const gx = right - left;
      const gy = down - up;
      const g = Math.sqrt(gx * gx + gy * gy);
      gradient[i] = g;
      if (g > maxG) maxG = g;
    }
  }

  // Normalize to 0–1
  if (maxG > 0) {
    for (let i = 0; i < total; i++) gradient[i] /= maxG;
  }

  return gradient;
}

// ---------------------------------------------------------------------------
// Depth-gradient-aware alpha mask
//
// Instead of a hard binary mask + spatial Gaussian blur (which creates halos),
// alpha ramps smoothly in depth-space.  At sharp depth edges (high gradient),
// the transition narrows to preserve crisp object silhouettes.
// ---------------------------------------------------------------------------

function smoothstep(edge0, edge1, x) {
  if (edge1 === edge0) return x >= edge1 ? 1 : 0;
  const t = Math.max(0, Math.min(1, (x - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}

function buildDepthAwareMask(depth, gradient, total, low, high, transitionWidth, isFirst, isLast) {
  const mask = new Uint8Array(total);

  for (let i = 0; i < total; i++) {
    const d = depth[i];

    // Modulate transition width by gradient:
    //   gradient ≈ 1 (sharp depth edge) → narrow transition → crisp silhouette
    //   gradient ≈ 0 (gradual change)   → full transition   → smooth blend
    const g  = gradient[i];
    const tw = transitionWidth * (1 - 0.85 * Math.min(1, g * 2));

    // Only apply transition at boundaries between adjacent layers.
    // First layer has no neighbour below; last layer has no neighbour above.
    const distLow  = isFirst ? Infinity : (d - low);
    const distHigh = isLast  ? Infinity : (high - d);
    const minDist  = Math.min(distLow, distHigh);

    if (minDist >= tw) {
      mask[i] = 255;
    } else if (minDist < -tw) {
      mask[i] = 0;
    } else {
      mask[i] = Math.round(255 * smoothstep(-tw, tw, minDist));
    }
  }

  return mask;
}

// ---------------------------------------------------------------------------
// Layer labels
// ---------------------------------------------------------------------------

function layerLabels(n) {
  if (n === 1) return ['background'];
  if (n === 2) return ['background', 'foreground'];
  if (n === 3) return ['background', 'midground', 'foreground'];
  // 4+: background, midground_1 … midground_N, foreground
  const labels = ['background'];
  for (let i = 1; i < n - 1; i++) labels.push(`midground_${i}`);
  labels.push('foreground');
  return labels;
}

// ---------------------------------------------------------------------------
// Main slicing pipeline
// ---------------------------------------------------------------------------

async function sliceLayers(sourcePath, rawDepth, srcWidth, srcHeight, nLayers, transitionWidth, baseName, outputDir, maxWidth) {
  const total = srcWidth * srcHeight;

  // 1. Normalize depth (percentile clamp + linear rescale)
  console.log('Normalizing depth...');
  const depth = normalizeDepth(rawDepth, total);

  // Print distribution after normalization
  const hist = new Uint32Array(256);
  for (let i = 0; i < total; i++) hist[depth[i]]++;
  console.log('  Normalized depth distribution:');
  for (let b = 0; b < 256; b += 32) {
    let c = 0;
    for (let j = b; j < Math.min(b + 32, 256); j++) c += hist[j];
    const pct = (100 * c / total).toFixed(1);
    console.log(`    ${String(b).padStart(3)}-${String(Math.min(b + 31, 255)).padStart(3)}: ${pct.padStart(5)}%  ${'#'.repeat(Math.round(pct))}`);
  }

  // 2. Multi-Otsu adaptive boundaries
  console.log(`Finding optimal ${nLayers}-layer boundaries (multi-Otsu)...`);
  const boundaries = multiOtsuThresholds(depth, total, nLayers);

  for (let i = 0; i < boundaries.length; i++) {
    const { low, high } = boundaries[i];
    let count = 0;
    for (let d = low; d <= high; d++) count += hist[d];
    console.log(`  Segment ${i + 1}: depth [${low}–${high}] → ${(100 * count / total).toFixed(1)}% of pixels`);
  }

  // 3. Depth gradient for edge-aware alpha
  console.log('Computing depth gradient...');
  const gradient = computeDepthGradient(depth, srcWidth, srcHeight);

  // 4. Optional downscale
  let pipeline = sharp(sourcePath).ensureAlpha();
  let workW = srcWidth, workH = srcHeight;
  let workDepth = depth, workGradient = gradient;

  if (maxWidth && srcWidth > maxWidth) {
    const scale = maxWidth / srcWidth;
    workW = maxWidth;
    workH = Math.round(srcHeight * scale);
    console.log(`  Downscaling source from ${srcWidth}×${srcHeight} to ${workW}×${workH}`);
    pipeline = pipeline.resize(workW, workH, { kernel: 'lanczos3' });

    const resized = await sharp(Buffer.from(depth), { raw: { width: srcWidth, height: srcHeight, channels: 1 } })
      .resize(workW, workH, { kernel: 'lanczos3' }).raw().toBuffer();
    workDepth = new Uint8Array(resized);
    workGradient = computeDepthGradient(workDepth, workW, workH);
  }

  // Load source as RGBA
  const { data: srcData } = await pipeline.raw().toBuffer({ resolveWithObject: true });

  fs.mkdirSync(outputDir, { recursive: true });

  const labels    = layerLabels(nLayers);
  const workTotal = workW * workH;

  // Z positions: proportional to each layer's midpoint depth
  const Z_FAR = -50, Z_NEAR = -2;
  const results = [];

  console.log(`Slicing into ${nLayers} layers...`);

  for (let i = 0; i < boundaries.length; i++) {
    const { low, high } = boundaries[i];
    const label = labels[i];
    const index = i + 1;

    // Z proportional to midpoint depth in the 0–255 range
    const midDepth = (low + high) / 2;
    const z = Math.round(Z_FAR + (Z_NEAR - Z_FAR) * (midDepth / 255));

    console.log(
      `  Layer ${String(index).padStart(2)}/${nLayers}` +
      `  depth [${low}–${high}]` +
      `  z=${z >= 0 ? '+' : ''}${z}` +
      `  label=${label}`
    );

    // Build depth-gradient-aware alpha mask
    const isFirst = (i === 0);
    const isLast  = (i === boundaries.length - 1);
    const mask = buildDepthAwareMask(workDepth, workGradient, workTotal, low, high, transitionWidth, isFirst, isLast);

    // Apply mask to source pixels
    const layerData = Buffer.from(srcData);
    for (let p = 0; p < workTotal; p++) {
      layerData[p * 4 + 3] = mask[p];
    }

    // Write PNG
    const zStr    = `z${String(Math.abs(z)).padStart(2, '0')}`;
    const filename = `${baseName}_layer_${String(index).padStart(2, '0')}_${zStr}_${label}.png`;
    const outPath  = path.join(outputDir, filename);

    await sharp(layerData, { raw: { width: workW, height: workH, channels: 4 } })
      .png()
      .toFile(outPath);

    results.push({ index, label, z, depthLo: low, depthHi: high, file: filename, path: outPath });
  }

  return results;
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

async function main() {
  const args = minimist(process.argv.slice(2), {
    string:  ['image', 'depth', 'output', 'name', 'colormap'],
    boolean: ['help'],
    default: { transition: 8, colormap: 'auto', 'max-width': 0 },
    alias:   { h: 'help' },
  });

  if (args.help || !args.image || !args.depth) {
    console.log(`
Usage:
  node depth_layer_slicer.js --image <path> --depth <path> [options]

Options:
  --image       Source image path (required)
  --depth       Depth map path (required)
  --output      Output directory (default: ./layers/<name>)
  --name        Base name for output files (default: source filename stem)
  --layers      Number of depth layers (default: 3)
  --transition  Alpha blend width in depth-value units (default: 8)
  --colormap    auto | grayscale | color (default: auto)
  --max-width   Cap output width in pixels (default: no cap)
    `);
    process.exit(args.help ? 0 : 1);
  }

  const baseName  = (args.name || path.basename(args.image, path.extname(args.image)))
    .toLowerCase().replace(/\s+/g, '_');
  const outputDir = args.output || path.join('layers', baseName);
  const nLayers   = parseInt(args.layers, 10) || 3;
  const transition = parseInt(args.transition, 10);

  console.log('\ndepth_layer_slicer v2');
  console.log(`  source     : ${args.image}`);
  console.log(`  depth      : ${args.depth}`);
  console.log(`  output     : ${outputDir}`);
  console.log(`  layers     : ${nLayers}`);
  console.log(`  transition : ${transition} depth units`);
  console.log();

  // Load and convert depth map
  console.log('Loading depth map...');
  let { depth, width: depthW, height: depthH } = await loadDepthAsGrayscale(args.depth, args.colormap);

  // Get source dimensions
  const srcMeta = await sharp(args.image).metadata();
  const srcW = srcMeta.width, srcH = srcMeta.height;

  // Resize depth to source resolution if needed
  if (depthW !== srcW || depthH !== srcH) {
    console.log(`  Resizing depth from ${depthW}×${depthH} to ${srcW}×${srcH}`);
    const resized = await sharp(Buffer.from(depth), { raw: { width: depthW, height: depthH, channels: 1 } })
      .resize(srcW, srcH, { kernel: 'lanczos3' }).raw().toBuffer();
    depth = new Uint8Array(resized);
  }

  const maxWidth = parseInt(args['max-width'], 10) || 0;

  const results = await sliceLayers(
    args.image, depth, srcW, srcH,
    nLayers, transition, baseName, outputDir, maxWidth,
  );

  const manifest = results.map(r => ({
    file:  r.file,
    label: r.label,
    z:     r.z,
  }));
  const manifestPath = path.join(outputDir, `${baseName}_layers.json`);
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
  console.log(`  Manifest: ${manifestPath}`);

  console.log(`\nDone. ${results.length} layers written to: ${outputDir}/`);
  for (const r of results) console.log(`  ${r.file}`);
}

main().catch(err => { console.error(err.message); process.exit(1); });
