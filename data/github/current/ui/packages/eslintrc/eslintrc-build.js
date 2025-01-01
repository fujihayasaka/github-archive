// This is an eslint configuration for build-time scripts. It should not be used any any code that is built into a
// browser bundle. If you are using this configuration, you probably also want to set your package.json's `dev` to
// true.

// eslint-disable-next-line import/no-commonjs, no-undef
module.exports = {
  env: {
    node: true,
    browser: false,
  },
  rules: {
    'i18n-text/no-en': 'off',
    'import/no-nodejs-modules': 'off',
    'no-console': 'off',
    'import/extensions': [
      'error',
      'ignorePackages',
      // allow extensions for esm imports
      {json: 'always', ts: 'allow', tsx: 'allow', js: 'allow', jsx: 'allow'},
    ],
  },
  overrides: [
    {
      files: ['*.js'],
      parser: null,
      parserOptions: {
        project: null,
      },
      rules: {
        '@typescript-eslint/no-var-requires': 'off',
        '@typescript-eslint/no-require-imports': 'off',
        'import/no-commonjs': 'off',
      },
    },
  ],
}
