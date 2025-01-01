// @ts-check

/** @type {import('eslint').Linter.Config} */
module.exports = {
  rules: {
    'ref-default-argument': require('./rules/ref-default-argument'),
  },
  configs: {
    recommended: require('./configs/recommended'),
  },
}
