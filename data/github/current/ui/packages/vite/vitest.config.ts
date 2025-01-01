import {defineConfig, mergeConfig} from 'vitest/config'
import {externalizeSourceDependenciesPlugin} from './plugins/externalize-source-dependencies-plugin.ts'
import {serveAssetsForSmokePlugin} from './plugins/serve-assets-for-smoke-plugin.ts'
import viteConfig from './vite.config.ts'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'

const isCI = Boolean(process.env.GITHUB_CI)
const ignoredStderrLogs = ['Lit is in dev mode.', 'Multiple versions of Lit loaded.']

const uiPackagesDir = 'ui/packages'
const workingDir = process.cwd()
const isPackageLevel = workingDir.includes(uiPackagesDir)
const SERVER_TEST_PATTERNS = [
  `${workingDir}/**/__tests__/*SSR.test.(tsx|ts|js)`,
  `${workingDir}/**/__tests__/*.server.test.(tsx|ts|js)`,
]

export default mergeConfig(
  viteConfig,
  defineConfig({
    define: {
      'process.env.TEST_RUNNER': JSON.stringify('vitest'),
      'process.env.TZ': JSON.stringify('UTC'),
    },
    plugins: [
      externalizeSourceDependenciesPlugin([
        /* @web/test-runner-commands needs to establish a web-socket
         * connection. It expects a file to be served from the
         * @web/dev-server. So it should be ignored by Vite */
        '/__web-dev-server__web-socket.js',
      ]),
    ],
    root: isPackageLevel ? workingDir : viteConfig.root,
    test: {
      watch: false,
      workspace: [
        {
          extends: true,
          test: {
            name: 'browser',
            include: isPackageLevel
              ? [`${workingDir}/**/__tests__/*.test.(tsx|ts|js)`]
              : [
                  'test/js/unit/**/test-*.(js|ts)',
                  'test/components/**/*-test.ts',
                  'ui/packages/**/__browser-tests__/*.test.ts',
                ],
            exclude: SERVER_TEST_PATTERNS,
            browser: {
              screenshotFailures: false,
              api: {
                host: 'github.localhost',
              },
              headless: true,
              enabled: true,
              provider: 'playwright',
              instances: [{browser: 'chromium'}],
            },
            setupFiles: isPackageLevel
              ? ['../browser-tests/vitest-bootstrap.js'] // must use a relative path because it's outside the root
              : ['ui/packages/browser-tests/vitest-bootstrap.js'],
          },
        },
        {
          extends: true,
          plugins: [serveAssetsForSmokePlugin()],
          test: {
            name: 'prod-smoke',
            include: [`test/js/test-prod-smoke-bootstrap.js`],
            browser: {
              screenshotFailures: false,
              headless: true,
              enabled: true,
              provider: 'playwright',
              instances: [{browser: 'chromium'}],
            },
          },
        },
        {
          extends: true,
          test: {
            name: 'server',
            environment: 'node',
            include: isPackageLevel ? SERVER_TEST_PATTERNS : [],
          },
        },
      ],
      server: {
        deps: {
          inline: true,
        },
      },
      reporters: isCI
        ? ['default', fullPathFromRoot('ui/packages/browser-tests/vitest-janky-reporter.ts')]
        : ['default'],
      onConsoleLog(log: string, type: 'stdout' | 'stderr'): boolean | void {
        if (isCI && type === 'stdout') {
          return false
        }
        if (type === 'stderr' && ignoredStderrLogs.some(ignoredLog => log.includes(ignoredLog))) {
          return false
        }
      },
      retry: isCI ? 4 : 1,
    },
  }),
)
