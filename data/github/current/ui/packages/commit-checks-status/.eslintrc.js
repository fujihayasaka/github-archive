// @ts-check

/** @type {import('eslint').Linter.Config} */
module.exports = {
  rules: {
    // temporary disable to incrementally remove barrel files
    'no-barrel-files/no-barrel-files': 'off',
    'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
    'react-google-translate/no-return-text-nodes': 'off',
  },
}
