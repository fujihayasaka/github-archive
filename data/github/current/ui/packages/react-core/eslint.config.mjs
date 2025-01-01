// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'
import {sortImportsConfig} from '@github-ui/eslintrc/configs/sort-imports'

export default [
  ...defaultConfig,
  sortImportsConfig,
  {
    rules: {
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@github-ui/github-monorepo/prefer-github-ui-react-query': 'off',
      '@github-ui/github-monorepo/no-query-client-provider': 'off',
      '@github-ui/github-monorepo/prefer-data-router': 'off',
      '@github-ui/github-monorepo/restrict-relay-imports': 'off',
    },
  },
]
