// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    files: ['package.json'],
    rules: {
      '@github-ui/github-monorepo/package-json-required-scripts': 'off',
      '@github-ui/github-monorepo/required-configuration-files': 'off',
    },
    languageOptions: {
      parserOptions: {
        project: null,
      },
    },
  },
]
