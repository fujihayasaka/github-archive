import compat from 'eslint-plugin-compat'
import delegatedEvents from 'eslint-plugin-delegated-events'
import escompat from 'eslint-plugin-escompat'
import eslintPluginUnicorn from 'eslint-plugin-unicorn'
import importPlugin from 'eslint-plugin-import'
import github from 'eslint-plugin-github'
import githubUiDotcomPrimer from '@github-ui/eslint-plugin-dotcom-primer'
import githubUiGithubMonorepo from '@github-ui/eslint-plugin-github-monorepo'
import githubUiUiCommands from '@github-ui/eslint-plugin-ui-commands'
import githubUiReact19Prep from '@github-ui/eslint-plugin-react-19-prep'
import globals from 'globals'
import i18nText from 'eslint-plugin-i18n-text'
import noBarrelFiles from 'eslint-plugin-no-barrel-files'
import pluginJest from 'eslint-plugin-jest'
import pluginQuery from '@tanstack/eslint-plugin-query'
import primerReact from 'eslint-plugin-primer-react'
import react from '@eslint-react/eslint-plugin'
import reactCompiler from 'eslint-plugin-react-compiler'
import reactGoogleTranslate from 'eslint-plugin-react-google-translate'
import relay from 'eslint-plugin-relay'
import ssrFriendly from 'eslint-plugin-ssr-friendly'
import testingLibrary from 'eslint-plugin-testing-library'
import unusedImports from 'eslint-plugin-unused-imports'
import wc from 'eslint-plugin-wc'
import path from 'path'
import {fixupPluginRules} from '@eslint/compat'
import {FlatCompat} from '@eslint/eslintrc'
import {parser, plugin} from 'typescript-eslint'
import {fileURLToPath} from 'url'
import {noRestrictedImportsRule, noRestrictedSyntaxRule} from './no-restricted.mjs'

const reactPlugin = (await import('eslint-plugin-react')).default

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

const flatCompat = new FlatCompat({
  baseDirectory: __dirname,
})

const githubFlatConfigs = github.getFlatConfigs()

const config = {
  languageOptions: {
    // for escompat
    globals: {
      ...globals.browser,
      ...globals.builtin,
    },
  },
  linterOptions: {
    reportUnusedDisableDirectives: 'error',
    reportUnusedInlineConfigs: 'error',
  },
  plugins: {
    compat,
    'delegated-events': fixupPluginRules(delegatedEvents),
    escompat,
    'primer-react': fixupPluginRules(primerReact),
    'ssr-friendly': fixupPluginRules(ssrFriendly),
    relay: fixupPluginRules(relay),
    '@github-ui/dotcom-primer': fixupPluginRules(githubUiDotcomPrimer),
    '@github-ui/github-monorepo': fixupPluginRules(githubUiGithubMonorepo),
    '@github-ui/ui-commands': fixupPluginRules(githubUiUiCommands),
    '@github-ui/react-19-prep': fixupPluginRules(githubUiReact19Prep),
    unicorn: eslintPluginUnicorn,
    'no-barrel-files': noBarrelFiles,
    'unused-imports': unusedImports,
    react: reactPlugin,
    'react-compiler': fixupPluginRules(reactCompiler),
    'react-google-translate': reactGoogleTranslate,
    '@typescript-eslint': plugin,
  },
  rules: {
    'react-google-translate/no-conditional-text-nodes-with-siblings': 'error',
    'react-google-translate/no-return-text-nodes': 'error',
    'react-compiler/react-compiler': 'error',
    'primer-react/a11y-link-in-text-block': 'error',
    'primer-react/a11y-use-next-tooltip': 'off',
    'no-barrel-files/no-barrel-files': 'error',
    'no-restricted-globals': 'error',
    // we are not using flow types
    'relay/generated-flow-types': 'off',
    'import/no-unresolved': ['error', {ignore: ['^plugin:.*']}],
    'import/extensions': [
      'error',
      'ignorePackages',
      {json: 'always', ts: 'never', tsx: 'never', js: 'never', jsx: 'never'},
    ],
    'wc/no-constructor': 'error',
    'wc/no-customized-built-in-elements': 'error',
    'wc/no-child-traversal-in-attributechangedcallback': 'error',
    'wc/no-child-traversal-in-connectedcallback': 'error',
    'wc/no-exports-with-element': 'error',
    'wc/no-method-prefixed-with-on': 'error',
    'wc/guard-define-call': 'error',
    'wc/tag-name-matches-class': ['error', {suffix: ['Element']}],
    'wc/file-name-matches-element': 'off',
    'wc/no-self-class': 'off',
    'compat/compat': ['error'],
    'delegated-events/global-on': ['error'],
    'delegated-events/no-high-freq': ['error'],
    'escompat/no-nullish-coalescing': 'off',
    // `unused-imports` plugin works like `no-unused-vars` but provides an autofix for the imports
    '@typescript-eslint/no-unused-vars': 'off',
    'unused-imports/no-unused-imports': [
      'error',
      {
        // allow AnythingController or AnythingElement side-effecting imports
        varsIgnorePattern: '^[A-Z][a-zA-Z]+(Controller|Element)$',
      },
    ],
    'unused-imports/no-unused-vars': [
      'error',
      {
        argsIgnorePattern: '^_',
        // allow vars starting with _ or AnythingController or AnythingElement
        varsIgnorePattern: '^(_|[A-Z][a-zA-Z]+(Controller|Element)$)',
        ignoreRestSiblings: true,
      },
    ],
    '@typescript-eslint/no-import-type-side-effects': 'error',
    '@typescript-eslint/explicit-module-boundary-types': 'off',
    '@typescript-eslint/no-non-null-assertion': ['error'],
    'valid-typeof': ['error', {requireStringLiterals: true}],
    'github/no-inner-html': 'off',
    '@github-ui/github-monorepo/restrict-package-deep-imports': 'error',
    '@github-ui/github-monorepo/filename-convention': 'error',
    'github/filenames-match-regex': ['off'], // imported from plugin:github/recommended; off in favor of rule above
    '@github-ui/github-monorepo/prefer-const-object-to-enum': 'error',
    '@github-ui/github-monorepo/prefer-route-id-as-var-name': 'error',
    ...noRestrictedSyntaxRule(),
    ...noRestrictedImportsRule(),
    'primer-react/no-system-props': ['error', {includeUtilityComponents: true}],
    'primer-react/a11y-tooltip-interactive-trigger': 'off',
    'primer-react/new-color-css-vars': 'error',
    'primer-react/no-deprecated-entrypoints': 'error',
    'primer-react/no-wildcard-imports': 'error',
    'react/no-danger': ['error'],
    'react/self-closing-comp': [
      'error',
      {
        component: true,
        html: true,
      },
    ],
    'react/forbid-component-props': ['error', {forbid: ['dangerouslySetInnerHTML']}],
    'id-denylist': [
      'error',
      // this name is used to render arbitrary text as HTML, which may allow
      // untrusted input to be displayed and open an XSS vulnerability
      //
      // Please look into sanitizing this value with `<SanitizedHtml /> or
      // whether you even need to use this part of React.
      'dangerouslySetInnerHTML',
    ],
    'react/prop-types': 'off',
    'react/jsx-no-constructed-context-values': ['error'],
    'react-hooks/exhaustive-deps': [
      'warn',
      {
        additionalHooks: 'useHydratedEffect',
      },
    ],
    'react/jsx-boolean-value': 'error',
    'unicorn/prefer-array-find': 'error',
    'unicorn/no-instanceof-array': 'error',
    'unicorn/prefer-date-now': 'error',
    'unicorn/custom-error-definition': 'error',
    'unicorn/no-unnecessary-await': 'error',
    '@typescript-eslint/parameter-properties': 'error',
  },
  settings: {
    polyfills: ['Request', 'window.customElements', 'window.requestIdleCallback'],
    'import/parsers': {
      '@typescript-eslint/parser': ['.ts', '.tsx'],
    },
    'import/internal-regex': '^@github-ui/',
    'import/resolver': {
      typescript: true,
      node: {
        extensions: ['.js', '.ts', '.tsx'],
        moduleDirectory: ['node_modules', 'app/assets/modules'],
      },
    },
    'jsx-a11y': {
      polymorphicPropName: 'as',
      polymorphicAllowList: ['Text', 'Box', 'Heading'],
    },
    react: {
      version: 'detect',
    },
    wc: {
      elementBaseClasses: ['LitElement'], // Recognize `LitElement` as a Custom Element base class
    },
  },
}

const overrides = [
  {
    ...react.configs['recommended-type-checked'],
    files: ['**/*.ts', '**/*.tsx'],
  },
  {
    files: ['**/*.ts', '**/*.tsx'],
    languageOptions: {
      parser,
      parserOptions: {
        project: ['**/tsconfig.json'],
      },
    },
    plugins: {
      '@typescript-eslint': plugin,
    },
    rules: {
      'no-throw-literal': 'off',
      '@typescript-eslint/no-empty-object-type': 'off',
      '@typescript-eslint/consistent-type-assertions': 'error',
      '@typescript-eslint/only-throw-error': 'error',
      '@typescript-eslint/no-unnecessary-type-assertion': 'error',
      '@typescript-eslint/no-confusing-non-null-assertion': 'error',
      '@typescript-eslint/no-extra-non-null-assertion': 'error',
      '@typescript-eslint/no-non-null-asserted-nullish-coalescing': 'error',
      '@typescript-eslint/no-non-null-asserted-optional-chain': 'error',
      '@typescript-eslint/consistent-type-imports': 'error',
      'react/no-unknown-property': ['error', {ignore: ['elementtiming']}],
      // typescript handles this for us, so we can avoid checking here - which avoids disabling for type issues
      '@typescript-eslint/no-namespace': 'off',

      // Disallow unnecessary type arguments when TypeScript infers them automatically
      '@typescript-eslint/no-unnecessary-type-arguments': 'error',

      // Disallow casting to `any` if a generic is expected to work
      '@typescript-eslint/no-unnecessary-type-constraint': 'error',
      // recommended by typescript-eslint as the typechecker handles these out of the box
      // https://typescript-eslint.io/linting/troubleshooting/performance-troubleshooting/#eslint-plugin-import
      'import/named': 'off',
      'import/namespace': 'off',
      'import/default': 'off',
      'import/no-named-as-default-member': 'off',

      // muting an expensive rule that scans jsdoc comments looking for @deprecated notes
      'import/no-deprecated': 'off',

      // disabled rules from eslint-react to slowly be enabled
      '@eslint-react/dom/no-dangerously-set-innerhtml': 'off',
      '@eslint-react/dom/no-dangerously-set-innerhtml-with-children': 'off',
      '@eslint-react/dom/no-missing-button-type': 'off',
      '@eslint-react/hooks-extra/no-direct-set-state-in-use-effect': 'off',
    },
  },
  {
    files: ['**/*.json'],
    languageOptions: {
      parserOptions: {
        project: null,
      },
    },
    plugins: {
      '@typescript-eslint': plugin,
    },
    rules: {
      '@typescript-eslint/no-unused-expressions': 'off',
    },
  },
  {
    ...githubUiGithubMonorepo.configs['package-json'],
    files: ['**/package.json'],
    languageOptions: {
      parserOptions: {
        project: null,
      },
    },
    plugins: {
      '@github-ui/github-monorepo': fixupPluginRules(githubUiGithubMonorepo),
    },
  },
  {
    files: ['**/*.d.ts'],
    plugins: {
      '@typescript-eslint': plugin,
    },
    rules: {
      '@typescript-eslint/no-unused-vars': 'off',
      'no-var': 'off',
    },
  },
  {
    files: ['**/*.stories.tsx', '**/*.stories.ts'],
    plugins: {
      '@typescript-eslint': plugin,
      'react-google-translate': reactGoogleTranslate,
    },
    rules: {
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@eslint-react/no-create-ref': 'off',
      '@eslint-react/no-unstable-context-value': 'off',
      '@eslint-react/no-nested-components': 'off',
      '@eslint-react/hooks-extra/no-direct-set-state-in-use-effect': 'off',
      'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
      'react-google-translate/no-return-text-nodes': 'off',
    },
  },
  {
    ...githubUiGithubMonorepo.configs.test,
    files: ['**/__browser-tests__/**/*.ts'],
    plugins: {
      '@github-ui/github-monorepo': fixupPluginRules(githubUiGithubMonorepo),
      'react-compiler': fixupPluginRules(reactCompiler),
    },
    rules: {
      'no-throw-literal': 'off',
      '@typescript-eslint/only-throw-error': 'error',
      '@typescript-eslint/no-non-null-assertion': ['off'],
      '@github-ui/github-monorepo/test-file-names': 'error',
      'react-compiler/react-compiler': 'error',
      '@github-ui/github-monorepo/no-direct-test-helper-imports': 'error',
      '@github-ui/github-monorepo/no-global-test-helpers': 'error',
    },
  },
  {
    files: ['**/js/unit/**/test-*.{js,ts}', '**/components/**/*-test.ts'],
    plugins: {
      '@github-ui/github-monorepo': fixupPluginRules(githubUiGithubMonorepo),
    },
    rules: {
      '@github-ui/github-monorepo/no-direct-test-helper-imports': 'error',
      '@github-ui/github-monorepo/no-global-test-helpers': 'error',
    },
  },
  {
    ...pluginJest.configs['flat/recommended'],
    files: ['**/__tests__/**/*.tsx', '**/__tests__/**/*.ts'],
  },
  {
    ...testingLibrary.configs['flat/react'],
    files: ['**/__tests__/**/*.tsx', '**/__tests__/**/*.ts'],
  },
  {
    ...githubUiGithubMonorepo.configs.test,
    files: ['**/__tests__/**/*.tsx', '**/__tests__/**/*.ts'],
  },
  {
    files: ['**/__tests__/**/*.tsx', '**/__tests__/**/*.ts'],
    plugins: {
      i18nText,
      jest: pluginJest,
      react: reactPlugin,
      '@github-ui/github-monorepo': fixupPluginRules(githubUiGithubMonorepo),
      '@typescript-eslint': plugin,
      'react-google-translate': reactGoogleTranslate,
      'react-compiler': fixupPluginRules(reactCompiler),
    },
    languageOptions: {
      globals: pluginJest.environments.globals.globals,
    },
    rules: {
      'no-throw-literal': 'off',
      '@typescript-eslint/only-throw-error': 'error',
      'i18n-text/no-en': 'off',
      'github/unescaped-html-literal': 'off',
      'react/jsx-no-constructed-context-values': 'off',
      '@typescript-eslint/no-non-null-assertion': ['off'],
      '@github-ui/github-monorepo/test-file-names': 'error',
      'jest/expect-expect': ['error', {assertFunctionNames: ['expect', 'expect*', 'verify*', 'validate*']}],
      'jest/no-commented-out-tests': 'off',
      'jest/no-disabled-tests': 'off',
      'testing-library/prefer-user-event': 'error',
      '@eslint-react/no-create-ref': 'off',
      '@eslint-react/no-unstable-context-value': 'off',
      '@eslint-react/hooks-extra/no-redundant-custom-hook': 'off',
      '@eslint-react/no-nested-components': 'off',
      '@eslint-react/hooks-extra/no-direct-set-state-in-use-effect': 'off',
      'react-compiler/react-compiler': 'off',
      'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
      'react-google-translate/no-return-text-nodes': 'off',
    },
  },
  {
    files: ['**/*.tsx'],
    plugins: {
      i18nText,
    },
    ignores: ['**/__tests__/**', '**/test-utils/**'],
    rules: {
      'i18n-text/no-en': 'off',
      ...ssrFriendly.configs.recommended.rules,
    },
  },
]

function addFilesKey(objectsArray, objectValuesArray) {
  return objectsArray.map(obj => ({
    ...obj,
    files: objectValuesArray,
  }))
}

const escompatForEslint = addFilesKey(escompat.configs['flat/typescript'], [
  '**/*.config.js',
  '**/*.config.mjs',
  '**/eslint.config.mjs',
  'eslint.config.mjs',
  '**/test/linting/*.js',
  '**/janky-reporter.mjs',
  '**/janky-formatter.js',
])

const configEsLintOverrides = [
  {
    ...githubFlatConfigs.internal,
    files: [
      '**/*.config.js',
      '**/*.config.mjs',
      '**/eslint.config.mjs',
      'eslint.config.mjs',
      '**/test/linting/*.js',
      '**/janky-reporter.mjs',
      '**/janky-formatter.js',
    ],
  },
  ...escompatForEslint,
  {
    files: [
      '**/*.config.js',
      '**/*.config.mjs',
      '**/eslint.config.mjs',
      '**/test/linting/*.js',
      '**/janky-reporter.mjs',
      '**/janky-formatter.js',
      '**/eslint-base.mjs',
      '**/eslint-default.mjs',
    ],
    plugins: {
      i18nText,
      escompat,
      'no-barrel-files': noBarrelFiles,
      '@typescript-eslint': plugin,
    },
    languageOptions: {
      parserOptions: {
        project: null,
      },
      globals: {
        ...globals.node,
        process: true,
        __dirname: true,
      },
    },
    rules: {
      '@typescript-eslint/no-var-requires': 'off',
      '@typescript-eslint/no-require-imports': 'off',
      'escompat/no-object-rest-spread': 'off',
      'escompat/no-optional-catch': 'off',
      'i18n-text/no-en': 'off',
      'import/no-commonjs': 'off',
      'import/no-nodejs-modules': 'off',
      'no-barrel-files/no-barrel-files': 'off',
      'no-console': 'off',
    },
  },
  {
    files: ['**/*/eslint.config.mjs'],
    languageOptions: {
      globals: {
        ...globals.node,
      },
    },
    rules: {
      'import/no-commonjs': 'off',
    },
  },
  // Due to the overrides in this plugin, and the split between config and overrides here, we needed to include this here
  ...githubUiUiCommands.configs['recommended-flat'].overrides,
]

/*
  We don't want to redefine plugins that are already defined here
  Certain plugins will redefine the same plugin. e.g. primer-react redefines
  the jsx-a11y and github plugins that we use here. So we should remove
  the plugins key.
*/
function removePluginsKey(data) {
  return data.map(obj => {
    const {plugins, ...rest} = obj
    return rest
  })
}

export const baseConfig = [
  {ignores: ['**/*__generated__*', '**/*.module.css.d.ts', '**/.storybook/**/*']},
  githubFlatConfigs.internal,
  githubFlatConfigs.recommended,
  githubFlatConfigs.browser,
  ...escompat.configs['flat/typescript'],
  ...githubFlatConfigs.typescript,
  importPlugin.flatConfigs.typescript,
  wc.configs['flat/recommended'],
  reactPlugin.configs.flat.recommended,
  reactPlugin.configs.flat['jsx-runtime'],
  // When 5.2.0 gets released https://github.com/facebook/react/tree/main/packages/eslint-plugin-react-hooks we
  // can update to reactHooks.configs['recommended-latest']
  ...flatCompat.extends('plugin:react-hooks/recommended'),
  ...pluginQuery.configs['flat/recommended'],
  // Maintain this order for primer-react/recommended, and github/react
  // github/react brings in jsx-a11y/recommended
  ...removePluginsKey(flatCompat.extends('plugin:primer-react/recommended')),
  githubFlatConfigs.react,
  githubUiGithubMonorepo.configs.react,
  relay.configs.strict,
  ...githubUiUiCommands.configs['recommended-flat'].config,
  githubUiDotcomPrimer.configs.recommended,
  githubUiReact19Prep.configs.recommended,
  ...flatCompat.extends('plugin:clsx/recommended'),
  config,
  ...overrides,
  ...configEsLintOverrides,
]
