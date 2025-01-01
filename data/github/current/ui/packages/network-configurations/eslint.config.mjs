// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      '@github-ui/github-monorepo/no-sx': 'off',
      '@github-ui/github-monorepo/prefer-data-router': 'off',
    },
  },
  {
    files: ['components/*'],
    rules: {
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },
]
