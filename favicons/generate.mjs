import { favicons } from 'favicons';
import { promises as fs } from 'fs';
import path from 'path';

const source = path.resolve(import.meta.dirname, '../contracts/dependencies/ercs-0/assets/erc-8270/logo.svg');
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
