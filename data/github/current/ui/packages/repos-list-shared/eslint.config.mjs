// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'
import {sortImportsConfig} from '@github-ui/eslintrc/configs/sort-imports'

export default [
  ...defaultConfig,
  sortImportsConfig,
  {
    rules: {
      'no-barrel-files/no-barrel-files': 'off',
      'prettier/prettier': ['error'],
      camelcase: 'error',
      'i18n-text/no-en': 'off',
      'import/no-deprecated': 'warn',
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },
]
