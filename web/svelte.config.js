import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';


const dev = process.argv.includes('dev');
const repoName = 'spesscomputer'; // 👈 change this

export default {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapter({
      pages: 'build',
      assets: 'build',
      fallback: 'index.html'
    }),
    appDir: 'app',
    paths: {
      base: dev ? '' : `/${repoName}`
    }
  }
};