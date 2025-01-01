// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      'no-barrel-files/no-barrel-files': 'off',
      '@github-ui/github-monorepo/no-sx': 'off',
    },
  },
]
