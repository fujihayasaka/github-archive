import escompat from 'eslint-plugin-escompat'
import eslint from '@eslint/js'
import eslintComments from 'eslint-plugin-eslint-comments'
import eslintPluginPrettierRecommended from 'eslint-plugin-prettier/recommended'
import github from 'eslint-plugin-github'
import globals from 'globals'
import i18nText from 'eslint-plugin-i18n-text'
import importPlugin from 'eslint-plugin-import'
import jsxA11y from 'eslint-plugin-jsx-a11y'
import noOnlyTests from 'eslint-plugin-no-only-tests'
import {defaultConfig} from '@github-ui/eslintrc'
import path from 'path'
import playwright from 'eslint-plugin-playwright'
import pluginJest from 'eslint-plugin-jest'
import pluginQuery from '@tanstack/eslint-plugin-query'
import React from 'react'
import reactHooks from 'eslint-plugin-react-hooks'
import ssrFriendly from 'eslint-plugin-ssr-friendly'
import testingLibrary from 'eslint-plugin-testing-library'
import tseslint, {parser, plugin} from 'typescript-eslint'
import unicorn from 'eslint-plugin-unicorn'
import unusedImports from 'eslint-plugin-unused-imports'
import {fixupPluginRules} from '@eslint/compat'
import {FlatCompat} from '@eslint/eslintrc'
import {fileURLToPath} from 'url'
import { sortImportsConfig } from '@github-ui/eslintrc/configs/sort-imports'
import reactPlugin from 'eslint-plugin-react'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

const flatCompat = new FlatCompat({
  baseDirectory: __dirname,
})

const githubFlatConfigs = github.getFlatConfigs()

// In flat, type checked shared configs include recommend:
// https://typescript-eslint.io/getting-started/typed-linting/
// Disabling for javascript files
const tseConfig = tseslint.config(
  tseslint.configs.recommendedTypeChecked,
  {
    files: ['**/*.js',  '**/*.mjs'],
    extends: [tseslint.configs.disableTypeChecked],
  },
)

const noRestrictedImportsConfig = {
  paths: [
    {
      name: 'react-dom/test-utils',
      importNames: ['act'],
      message: 'Please use the act from @testing-library/react instead to avoid potential mismatches',
    },
    {
      name: 'react',
      importNames: ['act'],
      message: 'Please use the act from @testing-library/react instead to avoid potential mismatches',
    },
    {
      name: 'react-router-dom',
      importNames: ['Link', 'NavLink', 'useNavigate', 'useSearchParams', 'useLinkClickHandler', 'Navigate'],
      message: 'Please use the components/hooks from client/router instead, to avoid issues related to turbo in dotcom',
    },
    {
      name: 'react',
      importNames: ['default', 'React'],
      message: 'Only destructured imports of react are allowed',
    },
    {
      name: 'lodash',
      message: "Please use 'lodash-es' as it better supports tree-shaking.",
    },
    {
      name: 'lodash-es',
      importNames: ['noop'],
      message: "Please use '@github-ui/noop' for consistency as the standard no-op function.",
    },
    {
      name: 'lodash-es',
      importNames: ['identity'],
      message: "Please use 'utils/identity' for consistency as the standard identity function.",
    },
    {
      name: 'lodash-es',
      importNames: ['partition'],
      message: "Please use 'utils/partition' for consistency as the standard partition function.",
    },
    {
      name: 'lodash-es',
      importNames: ['omit'],
      message: "Please use 'utils/omit' for consistency as the standard omit function.",
    },
    {
      name: 'lodash-es',
      importNames: ['isNull'],
      message: "Prefer using '=== null' instead for consistency.",
    },
    {
      name: 'lodash-es',
      importNames: ['isString'],
      message: `Prefer using 'typeof value === "string"' instead for consistency.`,
    },
    {
      name: 'lodash-es',
      importNames: ['isError'],
      message: `Prefer using 'value instanceof Error' instead for consistency.`,
    },
    {
      name: 'lodash-es',
      importNames: ['last'],
      message: `Prefer using 'list.at(-1)' instead for consistency.`,
    },
    {
      name: 'lodash-es',
      importNames: ['first'],
      message: `Prefer using 'list[0]' or 'list.at(0)' instead for consistency.`,
    },
    {
      name: 'lodash-es',
      importNames: ['uniqueId'],
      message: "Prefer using 'hooks/common/use-prefixed-id' instead.",
    },
    {
      name: '@primer/react',
      importNames: ['Avatar'],
      message: 'Use { GitHubAvatar } from @github-ui/github-avatar instead',
    },
    {
      name: '@github-ui/emoji-autocomplete',
      importNames: ['EmojiAutocomplete'],
      message: 'Use { EmojiAutocomplete } from components/common/emoji-autocomplete instead',
    },
  ],
  patterns: [
    {
      group: ['@primer/react/lib/*'],
      message:
        "Use of non-ESM version of Primer components not allowed. Change the path from 'lib' to 'lib-esm' when importing from within the package",
    },
  ],
}

const noRestrictedImportsPlaywrightConfig = {
  paths: [
    {
      name: 'lodash',
      message: 'Please use bundled utilities instead of pulling in third party dependencies.',
    },
    {
      name: 'lodash-es',
      message: 'Please use bundled utilities instead of pulling in third party dependencies.',
    },
    {
      name: '@playwright/test',
      importNames: ['default', 'test'],
      message: 'Please use fixtures/test-extended instead, which provides additional fixture utilities',
    },
  ],
}

// The `playwright/no-element-handle` restricts calls to `page.$` and `page.$$`, but it does not restrict
// calls to `elementHandle.$` and `elementHandle.$$`. So, these are some custom syntax rules to restrict those calls.
const noElementHandleSyntaxExtended = [
  // Disallow any calls like `el.$()` where `el` is not `page`, so it does not conflict with the `playwright/no-element-handle` rule.
  {
    selector: 'CallExpression[callee.object.type="Identifier"][callee.object.name!="page"][callee.property.name="$"]',
    message:
      'Prefer using the Locator API to select elements instead of `$`. (https://playwright.dev/docs/api/class-locator)',
  },
  {
    selector: 'CallExpression[callee.object.type="Identifier"][callee.object.name!="page"][callee.property.name="$$"]',
    message:
      'Prefer using the Locator API to select elements instead of `$$`. (https://playwright.dev/docs/api/class-locator)',
  },
]
/**
 * @type {import('eslint').Linter.Config['parserOptions']}
 * Parser Options configuration for non-client files
 */
const baseServerParserOptions = {
  ecmaVersion: 2018,
  sourceType: 'module',
  tsconfigRootDir: import.meta.dirname,
  project: ['./tsconfig.json'],
}

/**
 * @type {import('eslint').Linter.Config['parserOptions']}
 * Parser options configuration for client files
 */
const baseClientParserOptions = {
  ...baseServerParserOptions,
  ecmaFeatures: {
    jsx: true,
  },
}

const baseNoRestrictedSyntax = [
  {
    selector: 'TSEnumDeclaration',
    message: `
Typescript enums are weird and inefficient, a const object provides the same
level of type safety, but with a smaller output size, and better ergonomics,
since it doesn't require the access to be from the enum directly every time.

Compare:

## Using an enum

enum MyEnum {
A = 'A',
B = 'B'
}

generated output:

var MyEnum;
(function (MyEnum) {
MyEnum["A"] = "A";
MyEnum["B"] = "B";
})(MyEnum || (MyEnum = {}));

Why does typescript generate output like this?  Enums are designed to be
merge-able, so if an enum is defined, and in scope, attempting to redefine it only
extends the original enum - a bit strange

## Using a const object instead
const MyConstObjectEnum = {
A: 'A',
B: 'B'
} as const
type MyConstObjectEnum = typeof MyConstObjectEnum[keyof typeof MyConstObjectEnum]

You may notice we define a type with the same name as the object. This
works, since typescript disambiguates the type to be the object type, and
allows them both to be used interchangeably, depending on context.

The \`type\` validly becomes a string union of the values of the object \`"A" | "B"\`
however the value of the object MyConstObjectEnum is an object wit the keys/values A, B


Code output

const MyConstObjectEnum = {A: 'A', B: 'B'}

In both cases we can limit the accepted values to the values of the object/enum, however
using a const object has a significantly smaller runtime size, no _generated_ code output.
`,
  },
]
const noRestrictedSyntaxWithBuildItemsAndColumnsOverrides = [
  {
    selector: 'CallExpression[callee.name="buildInitialItemsAndColumns"][arguments.length=2]',
    message: 'Calls to "buildInitialItemsAndColumns" with a second argument is not allowed in production code',
  },
]

const noRestrictedSyntaxWithDataHelpersForTestsOnly = [
  {
    selector: 'CallExpression[callee.name="resetInitialState"]',
    message: 'Calls to "resetInitialState" are not allowed in production code',
  },
  {
    selector: 'CallExpression[callee.name="setApiMetadataForTests"]',
    message: 'Calls to "setApiMetadataForTests" are not allowed in production code',
  },
  {
    selector: 'CallExpression[callee.name="resetAliveConfigForTests"]',
    message: 'Calls to "resetAliveConfigForTests" are not allowed in production code',
  },
  {
    selector: 'CallExpression[callee.name="resetEnabledFeaturesForTests"]',
    message: 'Calls to "resetEnabledFeaturesForTests" are not allowed in production code',
  },
]

const noRestrictedSyntaxDirectInteractionWithQueryClient = [
  {
    selector: 'MemberExpression > Identifier[name="getQueryData"]',
    message:
      'Direct calls to "getQueryData" are not allowed. Please use existing functions in "query-client-api.ts" instead.',
  },
  {
    selector: 'MemberExpression > Identifier[name="setQueryData"]',
    message:
      'Direct calls to "setQueryData" are not allowed. Please use existing functions in "query-client-api.ts" instead.',
  },
  {
    selector: 'MemberExpression > Identifier[name="getQueriesData"]',
    message:
      'Direct calls to "getQueriesData" are not allowed. Please use existing functions in "query-client-api.ts" instead.',
  },
  {
    selector: 'MemberExpression > Identifier[name="setQueriesData"]',
    message:
      'Direct calls to "setQueriesData" are not allowed. Please use existing functions in "query-client-api.ts" instead.',
  },
]

const tsClientPluginConfig = {
  languageOptions: {
    parserOptions: {
      ...baseClientParserOptions,
      tsconfigRootDir: import.meta.dirname,
      project: './tsconfig.json',
    },
  },
}

const config = [
  sortImportsConfig,
  {
    plugins: {
      '@typescript-eslint': plugin,
      react: reactPlugin,
      import: importPlugin,
      'unused-imports': unusedImports,
      'no-only-tests': noOnlyTests,
      i18nText,
      'testing-library': testingLibrary,
      jest: pluginJest,
      escompat,
      'eslint-comments': eslintComments,
      'ssr-friendly': fixupPluginRules(ssrFriendly),
      pluginQuery,
      unicorn,
    },
    languageOptions: {
      globals: {
        ...globals.browser,
        ...globals.node,
      },
      parser,
      parserOptions: baseClientParserOptions,
    },
    // rules which apply to JS, TS, etc.
    rules: {
      '@github-ui/github-monorepo/prefer-github-ui-react-query': 'off',
      'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
      'react-google-translate/no-return-text-nodes': 'off',
      // stylistic rules
      'eol-last': ['error', 'always'],
      'no-empty': 'error',

      'import/first': 'error',
      'import/no-duplicates': 'error',

      'import/no-named-as-default-member': 'off',
      'import/named': 'off',
      'import/default': 'off',
      'import/namespace': 'off',
      'import/no-deprecated': 'off',

      'github/no-then': 'off',

      'no-console': 'error',

      // Custom exhaustive deps
      'react-hooks/exhaustive-deps': [
        'error',
        {
          additionalHooks: '^(useEventHandler$|^useCommands)$',
        },
      ],

      /*
        * By default we want to catch and warn about any places
        * that dangerouslySetInnerHTML so that these instead use
        * the `<SanitizedHtml />`component to ensure no unsafe DOM is
        * rendered to the user.
        */
      'react/no-danger': 'error',
      'react/jsx-boolean-value': ['error'],
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
      // avoid usage of closing jsx tags for elements that take no children
      'react/self-closing-comp': [
        'error',
        {
          component: true,
          html: true,
        },
      ],
      // code-quality rules
      radix: 'off',
      'react/jsx-no-constructed-context-values': 'error',
      'react/jsx-uses-react': 'off',
      'react/react-in-jsx-scope': 'off',
      'react/prop-types': 'off',
      'no-unsafe-finally': 'error',
      'no-unused-expressions': 'error',
      'no-var': 'error',
      'no-restricted-properties': [
        'error',
        {
          object: 'window',
          property: 'history',
          message: 'history methods should be used through `@github-ui/history`',
        },
        ...Object.keys(React).map(key => {
          return {
            object: 'React',
            property: key,
            message: `imports of \`React.${key}\` should not use the global React namespace, which is only provided for typings. Instead, \`import {${key}} from 'react'\``,
          }
        }),
        {
          object: 'window',
          property: 'localStorage',
          message:
            'localStorage should be used through `safeLocalStorage` to avoid issues with browsers that disallow accessing localStorage',
        },
        {
          object: 'window',
          property: 'sessionStorage',
          message:
            'sessionStorage should be used through `safeSessionStorage` to avoid issues with browsers that disallow accessing sessionStorage',
        },
        {
          object: 'localStorage',
          message:
            'localStorage should be used through `safeLocalStorage` to avoid issues with browsers that disallow accessing localStorage',
        },
        {
          object: 'sessionStorage',
          message:
            'sessionStorage should be used through `safeSessionStorage` to avoid issues with browsers that disallow accessing sessionStorage',
        },
      ],
      'no-restricted-globals': [
        'error',
        {
          name: 'localStorage',
          message:
            'localStorage should be used through `safeLocalStorage` to avoid issues with browsers that disallow accessing localStorage',
        },
        {
          name: 'sessionStorage',
          message:
            'sessionStorage should be used through `safeSessionStorage` to avoid issues with browsers that disallow accessing sessionStorage',
        },
        {
          name: 'history',
          message: 'history should be used through `@github-ui/history`',
        },
      ],
      'no-restricted-syntax': [
        'error',
        ...baseNoRestrictedSyntax,
        ...noRestrictedSyntaxWithBuildItemsAndColumnsOverrides,
        ...noRestrictedSyntaxWithDataHelpersForTestsOnly,
        ...noRestrictedSyntaxDirectInteractionWithQueryClient,
      ],
      'no-restricted-imports': [
        'error',
        {
          ...noRestrictedImportsConfig,
          patterns: [
            ...noRestrictedImportsConfig.patterns,
            /**
             * Don't allow @ngneat/falso for production code at all
             */
            {
              group: ['@ngneat/falso/*'],
              message: 'Falso for fake data should not be used in production code',
            },
            {
              group: ['**/fields/progress-bar/*'],
              message: 'Import parent component from `fields/progress-bar` and use `variant` prop instead',
            },
          ],
        },
      ],

      'jsx-a11y/label-has-associated-control': [
        'error',
        {
          controlComponents: ['Checkbox'],
          depth: 2,
        },
      ],

      'primer-react/a11y-tooltip-interactive-trigger': 'off',
      'primer-react/a11y-use-accessible-tooltip': 'off',
      'primer-react/enforce-css-module-default-import': [
        'warn',
        {
        enforceName: '(^styles$|Styles$)'
        },
      ],
      'primer-react/enforce-css-module-identifier-casing': 'off',

      /**
       * Rules inherited from the base @github/eslintrc package configuration that have not yet been configured in Memex.
       * We should go through these rules and add specific eslint-disables for any exceptions and fully enable these.
       */
      'github/prefer-observers': 'off',
      'ssr-friendly/no-dom-globals-in-constructor': 'off',
      'ssr-friendly/no-dom-globals-in-module-scope': 'off',
      '@github-ui/github-monorepo/package-json-ordered-fields': 'off',
      'no-barrel-files/no-barrel-files': 'off',
      '@github-ui/github-monorepo/no-sx': 'off',
      '@github-ui/github-monorepo/no-query-client-provider': 'off',
      '@github-ui/github-monorepo/filename-convention': 'off',
      '@github-ui/github-monorepo/restrict-relay-imports': 'off',
    },
    settings: {
      react: {
        version: 'detect',
      },
      'import/parsers': {
        '@typescript-eslint/parser': ['.ts', '.tsx'],
      },
      'import/resolver': {
        typescript: {
          project: './tsconfig.json',
        },
      },
    },
  },
]

const playwrightConfig = [
  {
    ...playwright.configs['flat/recommended'],
    files: ['src/playwright-tests/**/*', 'src/playwright-tests/**/*'],
    languageOptions: {
      globals: {
        ...globals.node,
      },
    },
    plugins: {
      playwright,
    },
    rules: {
      'no-restricted-imports': ['error', noRestrictedImportsPlaywrightConfig],

      // reject any usages of .only() in tests as we want all tests to run on CI
      'no-only-tests/no-only-tests': process.env.CI ? 'error' : 'warn',

      'playwright/no-element-handle': ['error'],
      'no-restricted-syntax': ['error', ...noElementHandleSyntaxExtended],

      // muting all these new rules for now as well
      'playwright/no-force-option': ['off'],
      'playwright/no-wait-for-timeout': ['off'],
      'playwright/no-eval': ['off'],
      'playwright/no-skipped-test': ['off'],
      'playwright/no-conditional-in-test': ['off'],
      'playwright/expect-expect': ['off'],
      'playwright/prefer-web-first-assertions': ['off'],

      // Playwright tests must not contain imports from the client directory
      // due to a Babel (used in Playwright) and how it transpiles some newer
      // TS syntax such as `const enum`
      'import/no-restricted-paths': [
        'error',
        {
          zones: [
            {target: './', from: '../tests/'},
            {target: './', from: '../client/'},
          ],
        },
      ],

      // tests do not need to be localized
      'i18n-text/no-en': 'off',
    },
  },
  {
    files: ['**/**/playwright.config.ts'],
    rules: {
      // ignore naming convention as this file needs to be named in a certain
      // way to be detected by ESLint
      'github/filenames-match-regex': ['off'],
      // muting any warning about upgrading to ES Modules for now
      'import/no-commonjs': ['off'],
    },
  },
]

const playwrightOverrides = tseslint.config(
  {
    files: ['src/playwright-tests/**/*.ts', 'src/playwright-tests/**/*.tsx'],
    extends: [tseslint.configs.recommendedTypeChecked],
    languageOptions: {
      parserOptions: {
        tsconfigRootDir: import.meta.dirname,
        project: 'src/playwright-tests/tsconfig.json',
      },
    },
    rules: {
      // report any issues where assertions are unnecessary
      '@typescript-eslint/no-non-null-assertion': 'error',

      // allow numbers and booleans to be used in template expressions
      '@typescript-eslint/restrict-template-expressions': 'off',

      '@typescript-eslint/consistent-type-imports': 'error',
      '@typescript-eslint/no-import-type-side-effects': 'error',
      // report any issues with unused variables, but allow `_` to be used as
      // a variable prefix to ignore this rule
      '@typescript-eslint/no-unused-vars': 'off',
      'unused-imports/no-unused-imports': 'error',
      'unused-imports/no-unused-vars': [
        'error',
        {ignoreRestSiblings: true, argsIgnorePattern: '^_', varsIgnorePattern: '^_'},
      ],

      // ensure all Promise-based APIs are handled correctly in tests
      '@typescript-eslint/no-floating-promises': 'error',
    },
    settings: {
      'import/resolver': {
        typescript: {
          project: 'src/playwright-tests/tsconfig.json',
        },
      },
    },
  },
)

const tsOverrides = tseslint.config(
  {
    files: ['**/*.ts', '**/*.tsx'],
    extends: [tseslint.configs.recommendedTypeChecked],
    rules: {
      // stylistic rules
      '@typescript-eslint/naming-convention': [
        'error',
        {
          selector: 'class',
          format: ['PascalCase'],
        },
        // replicates the pre-3.0 '@typescript-eslint/interface-name-prefix' rule
        {
          selector: 'interface',
          format: ['PascalCase'],
          custom: {
            regex: '^I[A-Z]',
            match: false,
          },
        },
      ],
      // tsconfig handles this check
      '@typescript-eslint/no-namespace': 'off',
      '@typescript-eslint/consistent-type-imports': 'error',
      '@typescript-eslint/no-import-type-side-effects': 'error',
      '@typescript-eslint/array-type': ['error', {default: 'generic'}],
      '@typescript-eslint/consistent-type-assertions': ['error', {assertionStyle: 'as'}],
      // code quality rules
      '@typescript-eslint/prefer-for-of': 'error',
      '@typescript-eslint/no-unused-vars': 'off', // handled by unused-imports plugin in inherited config
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-non-null-assertion': 'error',
      '@typescript-eslint/ban-ts-comment': 'off',
      '@typescript-eslint/restrict-template-expressions': ['off'],
      '@typescript-eslint/no-unsafe-assignment': ['off'],
      '@typescript-eslint/no-unsafe-member-access': ['off'],
      '@typescript-eslint/no-floating-promises': ['off'],
      '@typescript-eslint/no-misused-promises': ['off'],
      '@typescript-eslint/require-await': ['off'],

      'unicorn/consistent-function-scoping': ['error'],

      'primer-react/no-system-props': ['error', {includeUtilityComponents: true}],
    },
  },
  tsClientPluginConfig,
)

const overrides = [
  {
    // React components in the client bundle should not interact with DOM globals
    // within the module scope - this breaks import/require from a Node context
    // which is a key prerequsite for server-side rendering
    files: [`src/client/**/*.ts`, `src/client/**/*.tsx`],
    plugins: {
      'ssr-friendly': fixupPluginRules(ssrFriendly),
    },
    rules: {
      ...ssrFriendly.configs.recommended.rules,
    },
  },
  {
    files: [
      'src/stories/**/*.ts',
      'src/mocks/**/*.ts',
      '**/**/*-spec.ts',
      '**/**/fixtures/**/*.ts',
      '**/**/*-factory.ts',
    ],
    rules: {
      // disabling this rule for files that aren't part of the main bundle
      'i18n-text/no-en': 'off',
      // we use plenty of HTML in mock data or test files to test sanitization that it's not worth the effort to
      // lint every single time we use something that looks like unsafe HTML code
      'github/unescaped-html-literal': 'off',
    },
  },
  {
    files: ['src/tests/**/*', 'src/playwright-tests/**/*'],
    rules: {
      // disabling this rule for tests, since we commonly define functions near where they are used for convenience
      'unicorn/consistent-function-scoping': 'off',
      'import/no-nodejs-modules': 'off',
      // we use plenty of HTML in mock data or test files to test sanitization that it's not worth the effort to
      // lint every single time we use something that looks like unsafe HTML code
      'github/unescaped-html-literal': 'off',
      // TODO: remove this rule when it understands that `.innerText` is different from `.innerText()`
      'github/no-innerText': 'off',
    },
  },
  {
    files: ['src/stories/**/*.ts', 'src/mocks/**/*.ts'],
    rules: {
      'no-console': 'off',
    },
  },
  {
    files: [
      '**/**/eslint.config.mjs',
      '**/**/jest.config.js',
      '**/**/webpack.config.ts',
      'script/*.js',
      'script/*.mjs',
      'script/*.ts',
    ],
    rules: {
      'github/filenames-match-regex': ['off'],
      'no-console': 'off',
      'i18n-text/no-en': 'off',
      'import/no-nodejs-modules': 'off',
    },
  },
  {
    files: ['script/*.js', '**/**/eslint.config.mjs'],
    rules: {
      'import/no-commonjs': 'off',
      '@typescript-eslint/no-var-requires': 'off',
    },
  },
]

const webpackScriptJestOverrides = tseslint.config(
  {
    files: ['webpack.config.ts', 'webpack/*.ts', 'script/*.ts', 'jest.config.js'],
    extends: [tseslint.configs.recommendedTypeChecked],
    languageOptions: {
      parserOptions: {
        ...baseServerParserOptions,
        tsconfigRootDir: import.meta.dirname,
        project: 'tsconfig.webpack.json',
      },
    },
  },
)

const serverOverrides = tseslint.config(
  {
    files: ['src/server.ts'],
    extends: [tseslint.configs.recommendedTypeChecked],
    languageOptions: {
      parserOptions: {
        ...baseServerParserOptions,
        tsconfigRootDir: import.meta.dirname,
        project: 'tsconfig.server.json',
      },
    },
    rules: {
      'import/no-commonjs': 'off',
      'no-console': 'off',
    },
  },
)

const srcOverrides = [
  {
    files: ['src/server-dev.js'],
    rules: {
      'import/no-commonjs': 'off',
      '@typescript-eslint/no-var-requires': 'off',
      'no-console': 'off',
      'import/no-nodejs-modules': 'off',
    },
  },
  {
    files: [
      'src/client/state-providers/memex-items/memex-items-data.ts',
      'src/tests/**/*-test.ts',
      'src/tests/jest-setup.ts',
    ],
    rules: {
      'no-restricted-syntax': ['error', ...baseNoRestrictedSyntax],
    },
  },
  {
    files: ['src/client/from-react-shared/**/*', 'src/client/from-relay-shared/**/*'],
    rules: {
      'github/filenames-match-regex': ['off'],
      // temporary until Relay type checking is fixed
      '@typescript-eslint/no-unsafe-return': 'off',
      '@typescript-eslint/no-unsafe-call': 'off',
      '@typescript-eslint/no-unsafe-argument': 'off',
    },
  },
  {
    files: ['src/client/from-react-shared/**/__generated__/**/*.graphql.ts', 'dev-environment/mockServiceWorker.js'],
    rules: {
      'eslint-comments/no-unlimited-disable': 'off',
      'eslint-comments/no-use': 'off',
    },
  },
  {
    files: ['src/client/from-react-shared/**/*.test.*'],
    rules: {
      'i18n-text/no-en': 'off',
    },
  },
  {
    files: ['**/*.json'],
    rules: {
      'no-unused-expressions': 'off',
    },
  },
  {
    files: ['**/strings.ts'],
    rules: {
      'i18n-text/no-en': 'off',
    },
  },
  {
    files: [
      'src/client/state-providers/**/query-client-api/*.ts',
      'src/client/state-providers/**/query-client-api.ts',
    ],
    rules: {
      'no-restricted-syntax': [
        'error',
        ...baseNoRestrictedSyntax,
        ...noRestrictedSyntaxWithBuildItemsAndColumnsOverrides,
        ...noRestrictedSyntaxWithDataHelpersForTestsOnly,
      ],
    },
  },
]

const testConfigs = [
  {
    ...testingLibrary.configs['flat/react'],
    ...pluginJest.configs['flat/recommended'],
    files: ['src/tests/**/*.ts', 'src/tests/**/*.tsx'],
    rules: {
      'react-hooks/react-compiler': 'off',
      // reject any usages of .only() in tests as we want all tests to run on CI
      'no-only-tests/no-only-tests': process.env.CI ? 'error' : 'warn',

      // rules for test authoring and formatting
      'jest/no-conditional-expect': 'off',
      'jest/consistent-test-it': ['error'],
      'jest/expect-expect': [
        'error',
        {
          assertFunctionNames: ['expect*'],
          additionalTestBlockFunctions: [],
        },
      ],
      'jest/prefer-lowercase-title': [
        'error',
        {
          ignore: ['describe'],
        },
      ],
      'react/jsx-no-constructed-context-values': 'off',
      'testing-library/prefer-user-event': 'error',

      // skip any localization requirements for test directory
      'i18n-text/no-en': 'off',

      '@eslint-react/no-create-ref': 'off',
      '@eslint-react/no-unstable-context-value': 'off',
      '@eslint-react/ensure-forward-ref-using-ref': 'off',
      '@eslint-react/hooks-extra/no-unnecessary-use-prefix': 'off',
      '@eslint-react/no-nested-components': 'off',
    },
  },
  {
    files: ['src/tests/features/find-in-project-test.tsx'],
    rules: {
      'testing-library/no-container': 'off',
      'testing-library/no-node-access': 'off',
    },
  },
]

const testOverrides = tseslint.config(
  {
    files: ['src/tests/**/*.ts', 'src/tests/**/*.tsx'],
    extends: [tseslint.configs.recommendedTypeChecked],
    languageOptions: {
      parserOptions: {
        tsconfigRootDir: import.meta.dirname,
        sourceType: 'module',
        project: ['src/tests/tsconfig.json'],
      },
    },
    rules: {
      // enforcing this so that our tests are properly handling promises
      '@typescript-eslint/no-floating-promises': ['error'],

      // coding style rules that we could re-enable later
      '@typescript-eslint/no-non-null-assertion': ['off'],
      '@typescript-eslint/no-unused-vars': 'off', // handled by unused-imports plugin in inherited config
      '@typescript-eslint/no-explicit-any': ['off'],
      '@typescript-eslint/no-unsafe-assignment': ['off'],
      '@typescript-eslint/no-unsafe-member-access': ['off'],
      '@typescript-eslint/no-unsafe-call': ['off'],
      '@typescript-eslint/restrict-template-expressions': ['off'],
      '@typescript-eslint/no-unsafe-return': ['off'],
      '@typescript-eslint/no-unsafe-argument': ['off'],
      '@typescript-eslint/no-extra-semi': ['off'],
      '@typescript-eslint/consistent-type-imports': 'error',
      '@typescript-eslint/no-import-type-side-effects': 'error',
    },
    settings: {
      'import/parsers': {
        '@typescript-eslint/parser': ['.ts', '.tsx'],
      },
      'import/resolver': {
        typescript: {
          project: '/src/tests/tsconfig.json',
        },
      },
    },
  }
)

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
delete jsxA11y.flatConfigs.recommended.plugins

export default [
  {
    ignores: [
      'dist/',
      'node_modules/',
      '**/*.html',
      '**/*.ejs',
      'src/coverage/',
      'dev-environment/mockServiceWorker.js',
      '**/__generated__/**'
    ],
  },
  ...defaultConfig,
  eslint.configs.recommended,
  ...pluginQuery.configs['flat/recommended'],
  ...tseConfig,
  reactPlugin.configs.flat.recommended,
  reactHooks.configs.recommended,
  ...removePluginsKey(flatCompat.extends('plugin:primer-react/recommended')),
  jsxA11y.flatConfigs.recommended,
  githubFlatConfigs.recommended,
  ...githubFlatConfigs.typescript,
  importPlugin.flatConfigs.typescript,
  ...config,
  ...tsOverrides,
  ...overrides,
  ...webpackScriptJestOverrides,
  ...serverOverrides,
  ...srcOverrides,
  ...testConfigs,
  ...testOverrides,
  ...playwrightConfig,
  ...playwrightOverrides,
  eslintPluginPrettierRecommended,
  {
    files: ['src/**/*.+(js|jsx|ts|tsx)', 'script/**/*.+(js|ts|mjs)', 'webpack.config.ts'],
  },
]
