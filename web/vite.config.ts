import { defineConfig } from 'vite';
import { sveltekit } from '@sveltejs/kit/vite';

const codemirrorPackages = [
  '@codemirror/state',
  '@codemirror/view',
  '@codemirror/language',
  '@codemirror/commands',
  '@codemirror/search',
  '@codemirror/lint',
  '@codemirror/autocomplete',
  '@codemirror/stream-parser',
  '@lezer/common',
  '@lezer/highlight'
];

export default defineConfig({
  plugins: [sveltekit()],
  resolve: {
    dedupe: codemirrorPackages
  },
  optimizeDeps: {
    include: codemirrorPackages
  },
  ssr: {
    noExternal: codemirrorPackages
  },
  server: {
    allowedHosts: [ 'dev.home.nsarrazin.com']
  }
});