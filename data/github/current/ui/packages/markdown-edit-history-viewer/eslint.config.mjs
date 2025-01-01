// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'
import {sortImportsConfig} from '@github-ui/eslintrc/configs/sort-imports'

export default [
  ...defaultConfig,
  sortImportsConfig,
  {
    rules: {
      camelcase: 'off',
      'import/no-deprecated': 'warn',
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@github-ui/github-monorepo/no-use-feature-flags': 'warn',
      '@github-ui/github-monorepo/no-sx': 'off',
      '@github-ui/github-monorepo/prefer-data-router': 'off',
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
      '@github-ui/github-monorepo/restrict-relay-imports': 'off',
    },
  },
  {
    files: ['emojis.ts'],
    rules: {
      camelcase: 'off',
      '@github-ui/github-monorepo/restrict-relay-imports': 'off',
    },
  },
]
