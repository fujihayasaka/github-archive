import eslintConfigSharedComponents from '../eslint-config-shared-components/eslint-config-shared-components.mjs'

export default [
  ...eslintConfigSharedComponents,
  {
    rules: {
      // temporary disable to incrementally remove barrel files
      'no-barrel-files/no-barrel-files': 'off',
    },
  },
]
