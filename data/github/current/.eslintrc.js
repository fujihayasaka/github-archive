// @ts-check
const {baseConfig} = require('@github-ui/eslintrc')

/**
 * @type {import('eslint').Linter.Config}
 */
module.exports = {
  ...baseConfig,
  root: true,
  parserOptions: {
    project: ['tsconfig.global.json', 'tsconfig.wtr.json'],
    tsconfigRootDir: __dirname,
    extraFileExtensions: ['.json'],
  },
  overrides: [
    {
      files: ['package.json'],
      rules: {
        '@github-ui/github-monorepo/required-configuration-files': 'off',
      },
    },
  ],
}
