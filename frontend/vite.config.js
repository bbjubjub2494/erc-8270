import { defineConfig } from 'vite';
import { resolve } from 'path';
import { distDir as faviconsDir } from '@erc-xxxx/favicons';

export default defineConfig({
    publicDir: faviconsDir,
    build: {
        rollupOptions: {
            input: {
                main: resolve(__dirname, 'index.html'),
                mint: resolve(__dirname, 'mint.html'),
                deposit: resolve(__dirname, 'deposit.html'),
            },
        },
    },
});
