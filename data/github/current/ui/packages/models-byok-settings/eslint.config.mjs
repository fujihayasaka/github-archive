// @ts-check
import eslintConfigSharedComponents from '../eslint-config-shared-components/eslint-config-shared-components.mjs'

export default [
  ...eslintConfigSharedComponents,
  {
    rules: {
      camelcase: 'off', // keep off for `enabled_features` prop and feature flag names
    },
  },
]
