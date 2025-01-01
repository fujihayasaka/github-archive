import {defineConfig, mergeConfig} from 'vitest/config'
import {externalizeSourceDependenciesPlugin} from './plugins/externalize-source-dependencies-plugin.ts'
import {serveAssetsForSmokePlugin} from './plugins/serve-assets-for-smoke-plugin.ts'
import {transformViImportsPlugin} from './plugins/transform-vi-imports-plugin.ts'
import viteConfig from './vite.config.ts'
import {fullPathFromRoot, globFromRoot, rootPath} from '@github-ui/client-build-tools/path-utils'
import ssrShims from '@github-ui/ssr-shims'

const isVscodeExtension = Boolean(process.env.VITEST_VSCODE)
const isCI = Boolean(process.env.GITHUB_CI)
const isHeadedBrowser = Boolean(process.env.HEADED_BROWSER_ENABLED)
const ignoredStderrLogs = ['Lit is in dev mode.', 'Multiple versions of Lit loaded.', '[MSW] Warning']

const uiPackagesDir = 'ui/packages'
const workingDir = isVscodeExtension ? rootPath : process.cwd()
const isPackageLevel = workingDir.includes(uiPackagesDir)

const BASE_PORT = 63000
const DEFAULT_PORT = 63315

function generateUniquePort(): number {
  if (!isPackageLevel || isHeadedBrowser || isVscodeExtension) {
    return DEFAULT_PORT
  }
  const pathsToPortOffset = Object.fromEntries(
    globFromRoot('ui/packages/*/package.json')
      .map(path => path.replace('/package.json', ''))
      .map((path, index) => [path, index + 1]),
  )

  const pwd = process.env.PWD || process.cwd()
  const portOffset = pathsToPortOffset[pwd]

  if (!portOffset) {
    throw new Error(`Could not find UI package for ${pwd}`)
  }

  return BASE_PORT + portOffset
}

export default mergeConfig(
  viteConfig,
  defineConfig({
    optimizeDeps: {
      include: ['@oddbird/popover-polyfill', 'react-compiler-runtime'],
      esbuildOptions: {
        tsconfigRaw: {
          compilerOptions: {
            experimentalDecorators: true,
          },
        },
      },
    },
    define: {
      'process.env.TZ': JSON.stringify('UTC'),
    },
    plugins: [
      transformViImportsPlugin(),
      externalizeSourceDependenciesPlugin([
        /* @web/test-runner-commands within @open-wc needs to establish a web-socket
         * connection. It expects a file to be served from the
         * @web/dev-server. So it should be ignored by Vite */
        '/__web-dev-server__web-socket.js',
      ]),
    ],
    root: isPackageLevel ? workingDir : viteConfig.root,
    test: {
      dir: (() => {
        if (isVscodeExtension) {
          return rootPath
        }
        return isPackageLevel ? `${workingDir}` : 'test/js'
      })(),
      watch: false,
      passWithNoTests: true,
      retry: Number(process.env.TEST_RETRIES_TIMES ?? isCI ? 4 : 0),
      workspace: [
        {
          extends: true,
          define: {
            'process.env.HEADED_BROWSER_ENABLED': JSON.stringify(isHeadedBrowser),
          },
          test: {
            name: 'browser',
            include: ['**/*.browser.test.(tsx|js|ts)'],
            browser: {
              api: {
                host: 'github.localhost',
                port: generateUniquePort(),
              },
              headless: process.env.HEADED_BROWSER_ENABLED !== 'true',
              enabled: true,
              provider: 'playwright',
              instances: [{browser: 'chromium'}],
              screenshotFailures: false,
            },
            setupFiles: isPackageLevel ? ['../tests/bootstrap.js'] : ['ui/packages/tests/bootstrap.js'],
          },
        },
        {
          ...(isVscodeExtension ? {root: fullPathFromRoot('ui/packages')} : {}),
          extends: true,
          test: {
            name: 'server',
            environment: 'node',
            include: [`**/*.server.test.(tsx|ts|js)`],
          },
          resolve: {
            alias: ssrShims.ssrShimFileMap,
          },
        },
        {
          extends: true,
          plugins: [serveAssetsForSmokePlugin()],
          test: {
            name: 'prod-smoke',
            include: [`test-prod-smoke-bootstrap.js`],
            browser: {
              headless: true,
              enabled: true,
              provider: 'playwright',
              instances: [{browser: 'chromium'}],
              screenshotFailures: false,
            },
            setupFiles: ['ui/packages/tests/bootstrap-prod-smoke.js'],
          },
        },
      ],
      reporters: isCI ? ['default', fullPathFromRoot('ui/packages/tests/janky-reporter.ts'), 'junit'] : ['default'],
      outputFile: {
        junit: 'tmp/js-tests.xml',
      },
      onConsoleLog(log: string, type: 'stdout' | 'stderr'): boolean | void {
        if (isCI && type === 'stdout') {
          return false
        }
        if (isCI && type === 'stderr' && ignoredStderrLogs.some(ignoredLog => log.includes(ignoredLog))) {
          return false
        }
      },
    },
  }),
)
