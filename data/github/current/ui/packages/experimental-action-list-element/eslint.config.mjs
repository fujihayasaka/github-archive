// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },
]
