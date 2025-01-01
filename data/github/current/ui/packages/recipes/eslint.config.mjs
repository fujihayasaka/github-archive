// @ts-check
import eslintBuildConfig from '@github-ui/eslintrc/build'

export default [
  ...eslintBuildConfig,
  {
    rules: {
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },
]
