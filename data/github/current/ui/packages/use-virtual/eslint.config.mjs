import {defaultConfig} from '@github-ui/eslintrc'
import simpleImportSort from 'eslint-plugin-simple-import-sort'

export default [
  ...defaultConfig,
  {
    plugins: {
      'simple-import-sort': simpleImportSort,
    },
    rules: {
      camelcase: 'off',
      'simple-import-sort/imports': 'error',
      'simple-import-sort/exports': 'error',
      'import/newline-after-import': 'error',
      'import/no-deprecated': 'warn',
      'sort-imports': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
    settings: {
      'import/resolver': {
        node: {
          extensions: ['.js', '.ts', '.tsx'],
        },
        typescript: true,
      },
    },
  },
  {
    files: ['**/__tests__/*'],
    rules: {
      'github/unescaped-html-literal': 0,
    },
  },
]
