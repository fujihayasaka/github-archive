// @ts-check

/** @type {import('eslint').Linter.Config} */
module.exports = {
  rules: {
    '@github-ui/github-monorepo/react-partial-name': 'error',
    '@github-ui/github-monorepo/react-app-name': 'error',
    // enable on a per-package basis as migrated
    '@github-ui/github-monorepo/no-sx': 'off',
    '@github-ui/github-monorepo/no-use-feature-flags': 'off',
  },
}
