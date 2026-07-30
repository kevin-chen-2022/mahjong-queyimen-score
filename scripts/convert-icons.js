const { Resvg } = require('@resvg/resvg-js');
const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const svgPath = path.join(projectRoot, '麻将.svg');
const outDir = path.join(projectRoot, 'build-resources', 'icons');

if (!fs.existsSync(svgPath)) {
  console.error('SVG not found:', svgPath);
  process.exit(1);
}
fs.mkdirSync(outDir, { recursive: true });

const svg = fs.readFileSync(svgPath);

// Electron windows-icon sizes (for .ico generation: 16,24,32,48,64,128,256
// Android mipmap sizes: 48,72,96,144,192,512
const sizes = [16, 24, 32, 48, 64, 72, 96, 128, 144, 192, 256, 512];

for (const size of sizes) {
  const resvg = new Resvg(svg, { fitTo: { mode: 'width', value: size }, background: 'rgba(255,255,255,0)' });
  const pngData = resvg.render().asPng();
  const outPath = path.join(outDir, `icon-${size}.png`);
  fs.writeFileSync(outPath, pngData);
  console.log('wrote', path.basename(outPath), size);
}

// Also write "icon.png" as 512x512 default for general-purpose
fs.copyFileSync(
  path.join(outDir, 'icon-512.png'),
  path.join(projectRoot, 'build-resources', 'icon.png')
);
console.log('wrote build-resources/icon.png');
console.log('Done converting all icons.');
