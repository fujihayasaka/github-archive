// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      '@github-ui/github-monorepo/no-sx': 'off',
    },
  },
  {
    files: ['components/*'],
    rules: {
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },
]
