// @ts-check

/** @type {import('eslint').Linter.Config} */
module.exports = {
  rules: {
    'filename-convention': require('./rules/filename-convention'),
    'no-query-client-provider': require('./rules/no-query-client-provider'),
    'prefer-github-ui-react-query': require('./rules/prefer-github-ui-react-query'),
    'package-json-required-scripts': require('./rules/package-json-required-scripts'),
    'package-json-required-fields': require('./rules/package-json-required-fields'),
    'package-json-ordered-fields': require('./rules/package-json-ordered-fields'),
    'package-json-version-numbers': require('./rules/package-json-version-numbers'),
    'package-json-valid-exports': require('./rules/package-json-valid-exports'),
    'required-configuration-files': require('./rules/required-configuration-files'),
    'package-json-required-dev-dependencies': require('./rules/package-json-required-dev-dependencies'),
    'restrict-package-deep-imports': require('./rules/restrict-package-deep-imports'),
    'package-json-versions-in-sync': require('./rules/package-json-versions-in-sync'),
    'test-file-names': require('./rules/test-file-names'),
    'react-app-name': require('./rules/react-app-name'),
    'react-partial-name': require('./rules/react-partial-name'),
    'no-sx': require('./rules/no-sx'),
    'no-sx-components': require('./rules/no-sx-components'),
    'no-use-feature-flags': require('./rules/no-use-feature-flags'),
    'no-playwright-new-page': require('./rules/no-playwright-new-page'),
    'no-playwright-base-fixture': require('./rules/no-playwright-base-fixture'),
    'migrated-package-imports': require('./rules/migrated-package-imports'),
    'prefer-const-object-to-enum': require('./rules/prefer-const-object-to-enum'),
    'no-direct-test-helper-imports': require('./rules/no-direct-test-helper-imports'),
    'no-global-test-helpers': require('./rules/no-global-test-helpers'),
    'prefer-route-id-as-var-name': require('./rules/prefer-route-id-as-var-name'),
  },
  configs: {
    'package-json': require('./configs/package-json'),
    test: require('./configs/test'),
    react: require('./configs/react'),
  },
}
