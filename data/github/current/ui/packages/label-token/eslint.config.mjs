// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      '@github-ui/github-monorepo/no-use-feature-flags': 'warn',
      '@github-ui/github-monorepo/no-sx': 'off',
    },
  },
]
