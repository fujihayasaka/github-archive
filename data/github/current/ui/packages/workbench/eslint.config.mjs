// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'
import {sortImportsConfig} from '@github-ui/eslintrc/configs/sort-imports'

export default [
  ...defaultConfig,
  sortImportsConfig,
  {
    rules: {
      'prettier/prettier': ['error'],
      'no-barrel-files/no-barrel-files': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
      'import/no-deprecated': 'warn',
      '@github-ui/github-monorepo/prefer-github-ui-react-query': 'error',
      // This app cannot be migrated yet because of a dependency on a custom query cache
      '@github-ui/github-monorepo/no-query-client-provider': 'error',
      '@github-ui/github-monorepo/prefer-data-router': 'off',
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
  {
    files: ['**/**.stories.**'],
    rules: {
      'import/no-extraneous-dependencies': ['off'],
    },
  },
]
