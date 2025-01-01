// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'
import sortArrayValues from 'eslint-plugin-sort-array-values'

export default [
  ...defaultConfig,
  {
    plugins: {
      'sort-array-values': sortArrayValues,
    },
    rules: {
      'sort-array-values/sort-array-values': 'error',
    },
  },
]
