// @ts-check
import eslintBuildConfig from '@github-ui/eslintrc/build'

export default [
  ...eslintBuildConfig,
  {
    rules: {
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@github-ui/github-monorepo/react-partial-name': 'off',
      '@github-ui/github-monorepo/react-app-name': 'off',
      '@github-ui/github-monorepo/prefer-data-router': 'off',
    },
  },
  {
    ignores: ['__fixtures__'],
  },
]
