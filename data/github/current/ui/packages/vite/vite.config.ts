import {defineConfig} from 'vite'
import {getDefinePluginConfig} from '@github-ui/client-build-plugins/define'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'
import {dotcomCssPlugin} from './plugins/dotcom-css-plugin.ts'
import {dotcomEntryPlugin} from './plugins/dotcom-entry-plugin.ts'
import {dotcomReactPlugin} from './plugins/dotcom-react-plugin.ts'
import {dotcomWatchPlugin} from './plugins/dotcom-watch-plugin.ts'
import {alloyPlugin} from './plugins/alloy-plugin.ts'
import {dynamicElementsPlugin} from './plugins/dotcom-dynamic-elements-plugin.ts'
import {temporaryCommonjsPlugin} from './plugins/dotcom-commonjs-plugin.ts'

export default defineConfig({
  base: '/vite/',
  root: fullPathFromRoot(''),
  /**
   * The majority of the config resides in the following plugins
   */
  plugins: [
    alloyPlugin(),
    dotcomCssPlugin(),
    dotcomEntryPlugin(),
    dotcomReactPlugin(),
    dotcomWatchPlugin(),
    dynamicElementsPlugin(),
    temporaryCommonjsPlugin(),
  ],
  define: getDefinePluginConfig({bundler: 'vite'}),
  assetsInclude: ['**/*.glb'], // Additional static asset types to include
  optimizeDeps: {
    entries: [], // Do not auto-detect dependencies on startup. Let it happen as JS is imported.
    include: ['react-compiler-runtime'],
    esbuildOptions: {
      keepNames: true, // Preserve class names in esbuild for catalyst controllers
      tsconfigRaw: {
        compilerOptions: {
          experimentalDecorators: true,
        },
      },
    },
  },
  esbuild: {
    keepNames: true, // Preserve class names in esbuild for catalyst controllers
  },
  server: {
    allowedHosts: ['vite'],
    port: 3013, // This must match the nginx config
    strictPort: true,
    host: true, // listen on all addresses
    hmr: {
      path: '/hmr', // Custom path for HMR websocket so nginx has a keyword to look for
    },
  },
  clearScreen: false,
})
