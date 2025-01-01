// @ts-check
import {defaultConfig} from './eslint-default.mjs'

export default [
  ...defaultConfig,
  {
    rules: {
      '@github-ui/github-monorepo/package-json-required-scripts': 'off',
      '@github-ui/github-monorepo/required-configuration-files': 'off',
      '@github-ui/github-monorepo/package-json-required-dev-dependencies': 'off',
    },
  },
]
