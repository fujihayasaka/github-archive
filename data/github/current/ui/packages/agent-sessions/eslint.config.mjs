// @ts-check

import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    ignores: ['mocks/session_logs_response.json', 'mocks/session_logs_oswe_response.json'],
  },
]
