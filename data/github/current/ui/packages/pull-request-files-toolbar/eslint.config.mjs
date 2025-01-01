// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      '@tanstack/query/exhaustive-deps': 'off',
      '@github-ui/github-monorepo/no-sx': 'off',
    },
  },
]
