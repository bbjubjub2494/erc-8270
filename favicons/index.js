const { readFileSync } = require('fs');
const path = require('path');
exports.distDir = path.resolve(__dirname, 'dist');
exports.logoCid = readFileSync(path.join(exports.distDir, 'logo.svg.cid'), 'utf8').trim();
