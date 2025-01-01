// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      '@github-ui/github-monorepo/no-sx': 'off',
      '@github-ui/github-monorepo/restrict-relay-imports': 'off',
    },
  },
]
