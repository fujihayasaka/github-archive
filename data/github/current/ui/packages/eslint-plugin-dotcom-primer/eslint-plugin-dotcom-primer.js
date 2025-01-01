// @ts-check

/** @type {import('eslint').Linter.Config} */
module.exports = {
  rules: {
    'toast-migration': require('./rules/toast-migration'),
  },
  configs: {
    recommended: {
      rules: {
        '@github-ui/dotcom-primer/toast-migration': 'error',
      },
    },
  },
}
