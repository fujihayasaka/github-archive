// @ts-check
import eslintBuildConfig from '@github-ui/eslintrc/build'

export default [
  ...eslintBuildConfig,
  {
    rules: {
      '@github-ui/github-monorepo/required-configuration-files': 'off',
      '@github-ui/github-monorepo/package-json-required-dev-dependencies': 'off',
      'no-barrel-files/no-barrel-files': 'off',
    },
  },
]
