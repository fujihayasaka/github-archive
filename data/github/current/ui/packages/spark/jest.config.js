// @ts-check
const config = require('@github-ui/jest/config')

module.exports = {
  ...config,
  // Configure Jest to transform both vscode-languageserver-types and d3 packages
  transformIgnorePatterns: ['../../node_modules/(?!(vscode-languageserver-types|d3))'],
  moduleNameMapper: {
    // eslint-disable-next-line github/unescaped-html-literal
    '\\.css$': '<rootDir>/__tests__/__mocks__/styleMock.js',
  },
}
