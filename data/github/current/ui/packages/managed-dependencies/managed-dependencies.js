// @ts-check

/**
 * @type {Record<string, string>}
 * This is the list of "managed" dependencies. We generally want to keep this list small,
 * and only add dependencies which are intentionally controlled by a single team. We should
 * tend toward each package declaring specific version numbers so that package owners are
 * pinged as a codeowner when a dependency is updated.
 */
const managedDependencies = {
  '@eslint-react/eslint-plugin': '@github-ui/eslintrc',
  '@eslint/compat': '@github-ui/eslintrc',
  '@eslint/eslintrc': '@github-ui/eslintrc',
  '@eslint/js': '@github-ui/eslintrc',
  '@github/browser-support': '@npm-workspaces/core',
  '@github/catalyst': '@npm-workspaces/primer',
  '@github/combobox-nav': '@npm-workspaces/core',
  '@github/jtml': '@npm-workspaces/core',
  '@github/selector-observer': '@npm-workspaces/core',
  '@github/turbo': '@github-ui/turbo',
  '@primer/behaviors': '@npm-workspaces/primer',
  '@primer/css': '@npm-workspaces/primer',
  '@primer/css-legacy': '@npm-workspaces/primer',
  '@primer/live-region-element': '@npm-workspaces/primer',
  '@primer/octicons-react': '@npm-workspaces/primer',
  '@primer/primitives': '@npm-workspaces/primer',
  '@primer/react': '@npm-workspaces/primer',
  '@primer/react-brand': '@github-ui/swp-core',
  '@primer/view-components': '@npm-workspaces/primer',
  '@remix-run/router': '@github-ui/react-core',
  '@storybook/addon-actions': '@github-ui/storybook',
  '@storybook/addon-essentials': '@github-ui/storybook',
  '@storybook/jest': '@github-ui/storybook',
  '@storybook/preview-api': '@github-ui/storybook',
  '@storybook/react': '@github-ui/storybook',
  '@storybook/test': '@github-ui/storybook',
  '@tanstack/eslint-plugin-query': '@github-ui/eslintrc',
  '@tanstack/react-query': '@github-ui/react-query',
  '@tanstack/react-query-devtools': '@github-ui/react-core',
  '@testing-library/jest-dom': '@github-ui/jest',
  '@testing-library/react': '@github-ui/react-core',
  '@testing-library/user-event': '@github-ui/react-core',
  '@types/eslint': '@github-ui/eslintrc',
  '@types/react': '@github-ui/react-core',
  '@types/react-dom': '@github-ui/react-core',
  '@typescript-eslint/rule-tester': '@github-ui/eslintrc',
  '@typescript-eslint/utils': '@github-ui/eslintrc',
  '@typescript-eslint/types': '@github-ui/eslintrc',
  clsx: '@github-ui/react-core',
  esbuild: '@github-ui/vite',
  eslint: '@github-ui/eslintrc',
  'eslint-import-resolver-node': '@github-ui/eslintrc',
  'eslint-import-resolver-typescript': '@github-ui/eslintrc',
  'eslint-plugin-clsx': '@github-ui/eslintrc',
  'eslint-plugin-compat': '@github-ui/eslintrc',
  'eslint-plugin-custom-elements': '@github-ui/eslintrc',
  'eslint-plugin-delegated-events': '@github-ui/eslintrc',
  'eslint-plugin-escompat': '@github-ui/eslintrc',
  'eslint-plugin-github': '@github-ui/eslintrc',
  'eslint-plugin-i18n-text': '@github-ui/eslintrc',
  'eslint-plugin-import': '@github-ui/eslintrc',
  'eslint-plugin-jest': '@github-ui/eslintrc',
  'eslint-plugin-jsx-a11y': '@github-ui/eslintrc',
  'eslint-plugin-no-barrel-files': '@github-ui/eslintrc',
  'eslint-plugin-prettier': '@github-ui/eslintrc',
  'eslint-plugin-primer-react': '@github-ui/eslintrc',
  'eslint-plugin-react': '@github-ui/eslintrc',
  'eslint-plugin-react-compiler': '@github-ui/eslintrc',
  'eslint-plugin-react-google-translate': '@github-ui/eslintrc',
  'eslint-plugin-react-hooks': '@github-ui/eslintrc',
  'eslint-plugin-relay': '@github-ui/eslintrc',
  'eslint-plugin-ssr-friendly': '@github-ui/eslintrc',
  'eslint-plugin-testing-library': '@github-ui/eslintrc',
  'eslint-plugin-unicorn': '@github-ui/eslintrc',
  'eslint-plugin-unused-imports': '@github-ui/eslintrc',
  'eslint-plugin-wc': '@github-ui/eslintrc',
  'eslint-rule-documentation': '@github-ui/eslintrc',
  'fzy.js': '@npm-workspaces/core',
  history: '@github-ui/react-core',
  msw: '@github-ui/jest',
  react: '@github-ui/react-core',
  'react-dom': '@github-ui/react-core',
  'react-relay': '@npm-workspaces/relay',
  'react-router-dom': '@github-ui/react-core',
  'relay-runtime': '@github-ui/relay-environment',
  'relay-test-utils': '@npm-workspaces/relay',
  'styled-components': '@github-ui/react-core',
  typescript: '@npm-workspaces/core',
  'typescript-eslint': '@github-ui/eslintrc',
  webpack: '@github-ui/webpack',
}
module.exports.managedDependencies = managedDependencies

/**
 * @param {string | number} dependencyName
 * @returns {boolean}
 */
function isManagedDependency(dependencyName) {
  return Boolean(managedDependencies[dependencyName])
}
module.exports.isManagedDependency = isManagedDependency
