// @ts-check
import eslintBuildConfig from '@github-ui/eslintrc/build'

export default [
  ...eslintBuildConfig,
  {
    files: ['assets/*', '__tests__/__fixtures__/*'],
    rules: {
      'prettier/prettier': 'off',
    },
  },
]
