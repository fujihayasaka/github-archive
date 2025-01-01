module.exports = {
  extends: '../eslint-config-shared-components/eslint-config-shared-components.js',
  rules: {
    // disable to allow snake_case for some feature flags
    camelcase: 'off',
    // temporary disable to incrementally remove barrel files
    'no-barrel-files/no-barrel-files': 'off',
    '@github-ui/github-monorepo/no-sx': 'error',
    'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
    'react-google-translate/no-return-text-nodes': 'off',
  },
}
