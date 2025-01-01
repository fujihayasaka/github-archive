// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      '@github-ui/github-monorepo/no-sx': 'off',
      '@github-ui/github-monorepo/prefer-github-ui-react-query': 'off',
      '@github-ui/github-monorepo/no-query-client-provider': 'off',
    },
  },
]
