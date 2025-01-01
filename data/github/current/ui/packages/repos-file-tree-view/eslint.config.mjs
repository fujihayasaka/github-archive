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
      'prettier/prettier': ['error'],
      'no-barrel-files/no-barrel-files': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
      'simple-import-sort/imports': 'error',
      'simple-import-sort/exports': 'error',
      'import/newline-after-import': 'error',
      'import/no-deprecated': 'warn',
      'sort-imports': 'off',
      '@github-ui/github-monorepo/no-sx': 'off',
    },
    settings: {
      'import/parsers': {
        '@typescript-eslint/parser': ['.ts', '.tsx'],
      },
      'import/resolver': {
        typescript: {
          project: './tsconfig.json',
        },
      },
    },
  },
]
