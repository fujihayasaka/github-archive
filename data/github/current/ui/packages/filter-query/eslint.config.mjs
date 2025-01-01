// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'
import {sortImportsConfig} from '@github-ui/eslintrc/configs/sort-imports'

export default [
  ...defaultConfig,
  sortImportsConfig,
  {
    rules: {
      'prettier/prettier': ['error'],
      camelcase: 'error',
      'no-barrel-files/no-barrel-files': 'off',
      'i18n-text/no-en': 'off',
      'import/first': 'error',
      'import/no-duplicates': 'error',
      'import/no-deprecated': 'warn',
    },
  },
]
