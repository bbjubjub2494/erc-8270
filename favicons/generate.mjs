import { favicons } from 'favicons';
import { promises as fs } from 'fs';
import path from 'path';
import { CID } from 'multiformats/cid';
import { sha256 } from 'multiformats/hashes/sha2';
import * as dagPB from '@ipld/dag-pb';
import { UnixFS } from 'ipfs-unixfs';

const source = path.resolve(import.meta.dirname, 'logo.svg');
const outputDir = path.resolve(import.meta.dirname, 'dist');

const configuration = {
  path: '/',
  appName: 'Stake, Tokenized',
  appShortName: 'St',
  appDescription: 'Beacon chain validators as NFTs',
  background: '#333333',
  theme_color: '#333333',
  icons: {
    android: true,
    appleIcon: true,
    appleStartup: false,
    favicons: true,
    windows: false,
    yandex: false,
  },
};

async function generateFavicons() {
  console.log('Generating favicons from', source);

  const response = await favicons(source, configuration);

  await fs.mkdir(outputDir, { recursive: true });

  await fs.copyFile(source, path.join(outputDir, "logo.svg"));

  const logoData = await fs.readFile(source);
  const unixfsNode = new UnixFS({ type: 'file', data: logoData });
  const encoded = dagPB.encode({ Data: unixfsNode.marshal(), Links: [] });
  const hash = await sha256.digest(encoded);
  const cid = CID.createV1(dagPB.code, hash).toString();
  await fs.writeFile(path.join(outputDir, 'logo.svg.cid'), cid);
  console.log('IPFS CID for logo.svg:', cid);

  await Promise.all(
    response.images.map(async (image) => {
      const filePath = path.join(outputDir, image.name);
      await fs.writeFile(filePath, image.contents);
      console.log('Created:', image.name);
    })
  );

  await Promise.all(
    response.files.map(async (file) => {
      const filePath = path.join(outputDir, file.name);
      await fs.writeFile(filePath, file.contents);
      console.log('Created:', file.name);
    })
  );

  console.log('\nGenerated headTags HTML:');
  console.log(response.html.join('\n'));
}

generateFavicons().catch(console.error);
