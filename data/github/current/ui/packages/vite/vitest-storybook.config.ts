import {defineConfig, mergeConfig} from 'vitest/config'
import {storybookTest} from '@storybook/experimental-addon-test/vitest-plugin'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'
import baseConfig from './vitest.config.ts'

export default mergeConfig(
  baseConfig,
  defineConfig({
    test: {
      workspace: [
        {
          extends: true,
          plugins: [
            storybookTest({
              configDir: fullPathFromRoot('ui/packages/storybook/.storybook'),
              storybookScript: 'npm run storybook -- --ci',
              tags: {
                skip: ['flaky'],
              },
            }),
          ],
          test: {
            name: 'storybook',
            browser: {
              screenshotFailures: false,
              headless: true,
              enabled: true,
              provider: 'playwright',
              instances: [{browser: 'chromium'}],
            },
            setupFiles: [fullPathFromRoot('ui/packages/storybook/.storybook/vitest.setup.ts')],
          },
        },
      ],
    },
  }),
)
