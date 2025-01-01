// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'
import {sortImportsConfig} from '@github-ui/eslintrc/configs/sort-imports'

export default [
  ...defaultConfig,
  sortImportsConfig,
  {
    rules: {
      'prettier/prettier': ['error'],
      camelcase: 'error',
      'i18n-text/no-en': 'off',
      'import/no-deprecated': 'warn',
      // temporary disable to incrementally remove barrel files
      'no-barrel-files/no-barrel-files': 'off',
      'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
      'react-google-translate/no-return-text-nodes': 'off',
      '@github-ui/github-monorepo/no-sx': 'off',
    },
  },
]
