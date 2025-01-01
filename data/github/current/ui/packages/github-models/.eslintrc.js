module.exports = {
  extends: '../eslint-config-shared-components/eslint-config-shared-components.js',
  rules: {
    '@github-ui/github-monorepo/no-sx': 'warn',
    // TODO: Remove these exceptions slowly using auto-fix or manual fixes
    //       in smaller PRs so that we can see the impact of the changes.
    camelcase: 'off',
    '@typescript-eslint/await-thenable': 'off',
    '@typescript-eslint/restrict-template-expressions': 'off',
    '@typescript-eslint/no-floating-promises': 'off',
    '@typescript-eslint/no-misused-promises': 'off',
    '@typescript-eslint/no-redundant-type-constituents': 'off',
    '@typescript-eslint/no-unsafe-argument': 'off',
    '@typescript-eslint/no-unsafe-enum-comparison': 'off',
    '@typescript-eslint/no-unsafe-return': 'off',
    '@typescript-eslint/require-await': 'off',
    '@typescript-eslint/unbound-method': 'off',
    'jest/consistent-test-it': 'off',
    'jest/prefer-lowercase-title': 'off',
    'simple-import-sort/imports': 'off',
    'import/newline-after-import': 'off',
    'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
    'react-google-translate/no-return-text-nodes': 'off',
  },
}
