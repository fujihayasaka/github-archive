// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@github-ui/github-monorepo/no-sx': 'off',
      '@github-ui/github-monorepo/prefer-data-router': 'off',
      '@github-ui/github-monorepo/restrict-relay-imports': 'off',
    },
  },
]
