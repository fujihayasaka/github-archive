// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      '@github-ui/github-monorepo/prefer-data-router': 'off',
    },
  },
]
