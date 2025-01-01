// @ts-check

/** @type {import('eslint').Linter.Config} */
module.exports = {
  rules: {
    'require-children': require('./rules/require-children'),
    'toast-migration': require('./rules/toast-migration'),
  },
  configs: {
    recommended: {
      rules: {
        '@github-ui/dotcom-primer/require-children': [
          'error',
          {
            parent: 'ChartCard',
            child: 'ChartCard.Title',
            message: 'Including <ChartCard.Title> improves chart accessibility.',
            module: '@github-ui/chart-card',
          },
          {
            parent: 'ChartCard',
            child: 'ChartCard.Chart',
            module: '@github-ui/chart-card',
          },
        ],
        '@github-ui/dotcom-primer/toast-migration': 'error',
      },
    },
  },
}
