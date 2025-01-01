import {defaultConfig} from '@github-ui/eslintrc'
import i18nText from 'eslint-plugin-i18n-text'
import simpleImportSort from 'eslint-plugin-simple-import-sort'

export default [
  ...defaultConfig,
  {
    plugins: {
      i18nText,
      'simple-import-sort': simpleImportSort,
    },
    rules: {
      'relay/must-colocate-fragment-spreads': 'off',
      camelcase: 'off',
      'simple-import-sort/imports': 'error',
      'simple-import-sort/exports': 'error',
      'import/newline-after-import': 'error',
      'import/no-deprecated': 'warn',
      'sort-imports': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@github-ui/github-monorepo/no-use-feature-flags': 'warn',
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
