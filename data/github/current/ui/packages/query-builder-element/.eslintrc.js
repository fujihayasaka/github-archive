// @ts-check

/** @type {import('eslint').Linter.Config} */
module.exports = {
  rules: {
    // temporary disable to incrementally remove barrel files
    'no-barrel-files/no-barrel-files': 'off',
    '@typescript-eslint/no-non-null-assertion': 'off',
  },
}
