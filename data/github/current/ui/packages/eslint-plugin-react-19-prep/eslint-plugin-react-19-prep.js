// @ts-check

/** @type {import('eslint').Linter.Config} */
module.exports = {
  rules: {
    'ref-default-argument': require('./rules/ref-default-argument'),
    'no-implicit-ref-callback-return': require('./rules/no-implicit-ref-callback-return'),
  },
  configs: {
    recommended: require('./configs/recommended'),
  },
}
