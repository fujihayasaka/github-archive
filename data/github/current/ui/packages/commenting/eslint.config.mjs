// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'
import {sortImportsConfig} from '@github-ui/eslintrc/configs/sort-imports'
import i18nText from 'eslint-plugin-i18n-text'

export default [
  ...defaultConfig,
  sortImportsConfig,
  {
    plugins: {
      i18nText,
    },
    rules: {
      'relay/must-colocate-fragment-spreads': 'off',
      camelcase: 'off',
      'import/no-deprecated': 'warn',
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@github-ui/github-monorepo/no-use-feature-flags': 'warn',
      '@github-ui/github-monorepo/no-sx': 'off',
      '@github-ui/github-monorepo/restrict-relay-imports': 'off',
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
