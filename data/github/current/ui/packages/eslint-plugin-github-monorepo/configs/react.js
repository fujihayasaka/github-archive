// @ts-check

/** @type {import('eslint').Linter.Config} */
module.exports = {
  rules: {
    '@github-ui/github-monorepo/react-partial-name': 'error',
    '@github-ui/github-monorepo/react-app-name': 'error',
    '@github-ui/github-monorepo/no-sx': 'error',
    '@github-ui/github-monorepo/no-sx-components': 'error',
    '@github-ui/github-monorepo/no-use-feature-flags': 'off',
    '@github-ui/github-monorepo/prefer-data-router': 'error',
    '@github-ui/github-monorepo/restrict-relay-imports': 'error',
    '@github-ui/github-monorepo/prefer-github-ui-react-query': 'error',
    '@github-ui/github-monorepo/no-query-client-provider': 'error',
    '@github-ui/github-monorepo/require-zod-v4': 'error',
  },
}
