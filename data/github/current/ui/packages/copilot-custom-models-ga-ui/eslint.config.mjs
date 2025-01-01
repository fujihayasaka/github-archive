// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      'no-barrel-files/no-barrel-files': 'off',
      'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
      'react-google-translate/no-return-text-nodes': 'off',
      '@github-ui/github-monorepo/no-sx': 'off',
      '@github-ui/github-monorepo/prefer-data-router': 'off',
      '@github-ui/github-monorepo/restrict-relay-imports': 'off',
    },
  },
]
