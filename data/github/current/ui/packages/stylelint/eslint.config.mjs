// @ts-check
import eslintBuildConfig from '@github-ui/eslintrc/build'

export default [
  ...eslintBuildConfig,
  {
    rules: {
      'jest/no-export': 'off',
      '@github-ui/github-monorepo/test-file-names': 'off',
      '@github-ui/github-monorepo/vitest-test-file-names': 'off',
    },
  },
]
