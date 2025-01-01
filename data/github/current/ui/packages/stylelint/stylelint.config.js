// @ts-check

/**
 * @type {import('stylelint').Config}
 */
const config = {
  extends: ['@primer/stylelint-config'],
  ignoreFiles: ['js', 'json', 'ts', 'graphql', 'md', 'mdx', 'cjs', 'html', 'mjs', 'snap', 'yml'].map(
    ext => `**/*.${ext}`,
  ),
  quiet: true,
  cache: true,
  rules: {
    // Turning this off because seeing a lot of false errors
    'declaration-property-value-no-unknown': null,
  },
  overrides: [
    // Marketing stylesheets will use variables outside of primer system
    {
      files: [
        'app/assets/stylesheets/marketing/**/*.scss',
        'ui/packages/consent-experience/',
        'ui/packages/landing-pages/',
        'ui/packages/newsroom/',
        'ui/packages/webgl-globe/',
      ],
      rules: {
        'primer/colors': null,
      },
    },
  ],
}

module.exports = config
