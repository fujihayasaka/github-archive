// @ts-check
import globals from 'globals'

import eslintBuildConfig from '@github-ui/eslintrc/build'

export default [
  ...eslintBuildConfig,
  {
    languageOptions: {
      globals: {
        ...globals.mocha,
      },
    },
    rules: {
      // temporary disable to incrementally remove barrel files
      'no-barrel-files/no-barrel-files': 'off',
      'i18n-text/no-en': 'off',
    },
  },
]
