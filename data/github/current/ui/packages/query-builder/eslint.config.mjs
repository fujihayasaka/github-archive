// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      'no-barrel-files/no-barrel-files': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@github-ui/github-monorepo/no-use-feature-flags': 'warn',
      '@github-ui/github-monorepo/no-sx': 'off',
    },
  },
]
