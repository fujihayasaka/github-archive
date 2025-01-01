import {defaultConfig} from '@github-ui/eslintrc'
import simpleImportSort from 'eslint-plugin-simple-import-sort'

export default [
  ...defaultConfig,
  {
    plugins: {
      'simple-import-sort': simpleImportSort,
    },
    rules: {
      'no-barrel-files/no-barrel-files': 'off',
      camelcase: 'off',
      'simple-import-sort/imports': 'error',
      'simple-import-sort/exports': 'error',
      'import/newline-after-import': 'error',
      'import/no-deprecated': 'warn',
      'sort-imports': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
      'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
      'react-google-translate/no-return-text-nodes': 'off',
      '@github-ui/github-monorepo/no-sx': 'off',
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
  {
    files: ['emojis.ts'],
    rules: {
      camelcase: 'off',
    },
  },
]
