// @ts-check
import eslintBuildConfig from '@github-ui/eslintrc/build'

export default [
  ...eslintBuildConfig,
  {
    rules: {
      '@github-ui/github-monorepo/package-json-required-scripts': 'off',
    },
  },
]
