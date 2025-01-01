import {baseConfig} from './eslint-base.mjs'

export const legacyConfig = [
  ...baseConfig,
  {
    files: ['**/package.json'],
    rules: {
      '@github-ui/github-monorepo/package-json-required-fields': 'off',
    },
  },
]
