// @ts-check
import eslintConfigSharedComponents from '../eslint-config-shared-components/eslint-config-shared-components.mjs'

export default [
  ...eslintConfigSharedComponents,
  {
    rules: {
      'no-barrel-files/no-barrel-files': 'off',
    },
  },
]
