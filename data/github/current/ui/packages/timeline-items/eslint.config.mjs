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
    files: ['components/stories/*'],
    rules: {
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },
]
