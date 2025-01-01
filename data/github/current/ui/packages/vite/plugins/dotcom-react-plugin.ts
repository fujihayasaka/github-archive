import reactSwcPlugin from '@vitejs/plugin-react-swc'
import swcConfig from '@github-ui/swc/config'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'
import {runReactCompiler} from '@github-ui/client-build-plugins/react-compiler'
import type {PluginOption} from 'vite'

/**
 * @vitejs/plugin-react-swc normally injects this preamble into the index.html. Given we don't
 * use have index.html in the dotcom, we need to inject the preamble into a js file
 * instead so that it's present before any React code is run.
 *
 * See https://vite.dev/guide/backend-integration.html#backend-integration and search for "React" for more details
 */
let serverBase = '/'
function generatePreamble() {
  return `import { injectIntoGlobalHook } from "${serverBase}@react-refresh";
injectIntoGlobalHook(window);
window.$RefreshReg$ = () => {};
window.$RefreshSig$ = () => (type) => type;
`
}

/**
 * These entry files are always loaded early in the page load, so we will use them to inject the code
 */
const filesToInject = new Set(['app/assets/modules/environment.ts'].map(fullPathFromRoot))

export function dotcomReactPlugin(): PluginOption {
  return [
    {
      name: 'dotcom-react-refresh-plugin',
      apply: 'serve',
      configureServer(server) {
        serverBase = server.config.base
      },
      transform(code, id) {
        if (filesToInject.has(id)) {
          return {
            code: generatePreamble() + code,
            map: null,
          }
        }
      },
    },
    {
      name: 'dotcom-react-compiler-plugin',
      transform: runReactCompiler,
    },
    reactSwcPlugin({tsDecorators: true, plugins: swcConfig.jsc?.experimental?.plugins}),
  ]
}
