// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'
import {sortImportsConfig} from '@github-ui/eslintrc/configs/sort-imports'

export default [
  ...defaultConfig,
  sortImportsConfig,
  {
    rules: {
      'no-barrel-files/no-barrel-files': 'off',
      '@github-ui/github-monorepo/prefer-github-ui-react-query': 'off',
      '@github-ui/github-monorepo/no-query-client-provider': 'off',
    },
  },
]
