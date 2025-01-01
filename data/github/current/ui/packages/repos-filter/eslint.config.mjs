import {defaultConfig} from '@github-ui/eslintrc'
import prettier from 'eslint-plugin-prettier'
import simpleImportSort from 'eslint-plugin-simple-import-sort'

export default [
  ...defaultConfig,
  {
    plugins: {
      prettier,
      'simple-import-sort': simpleImportSort,
    },
    rules: {
      // temporary disable to incrementally remove barrel files
      'no-barrel-files/no-barrel-files': 'off',
      'prettier/prettier': ['error'],
      camelcase: 'error',
      'simple-import-sort/imports': 'error',
      'simple-import-sort/exports': 'error',
      'i18n-text/no-en': 'off',
      'import/newline-after-import': 'error',
      'import/no-deprecated': 'warn',
      'sort-imports': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },
]
