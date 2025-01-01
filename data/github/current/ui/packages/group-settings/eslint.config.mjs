// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
      'react-google-translate/no-return-text-nodes': 'off',
      '@github-ui/github-monorepo/no-sx': 'off',
      '@github-ui/github-monorepo/prefer-data-router': 'off',
    },
  },
]
