// @ts-check

/**
 * @type {import('eslint').Linter.RulesRecord}
 */
module.exports.noRestrictedSyntaxRules = {
  'no-restricted-syntax': [
    'error',
    {
      selector: "TSNonNullExpression>CallExpression[callee.property.name='getAttribute']",
      message: "Please check for null or use  `|| ''` instead of `!` when calling `getAttribute`",
    },
    {
      selector: "NewExpression[callee.name='URL'][arguments.length=1]",
      message: 'Please pass in `window.location.origin` as the 2nd argument to `new URL()`',
    },
    {
      selector: "CallExpression[callee.name='unsafeHTML']",
      message: 'Use unsafeHTML sparingly. Please add an eslint-disable comment if you want to use this',
    },
  ],
}

/**
 * @type {import('eslint').Linter.RulesRecord}
 */
module.exports.noRestrictedImportsRule = {
  'no-restricted-imports': [
    'error',
    {
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
          name: '@github-ui/failbot',
          importNames: ['reportError'],
          message:
            'Calling `reportError` directly is deprecated. To report errors to sentry, let them bubble to the document naturally or re-throw them. If they get caught by calling code you wish to avoid, wrap the re-throw in a setTimeout.',
        },
        {
          name: '@github/hotkey',
          message: 'Please import from @github-ui/hotkey instead',
        },
        {
          name: '@github/jtml',
          message: 'Use the shimmed version of jtml instead. See @github-ui/jtml-shimmed',
        },
        {
          // TODO: Once eslint is upgraded to v9, this rule can be broken out into 2 separate rules.
          name: '@primer/react',
          importNames: ['Avatar', 'ThemeProvider'],
          message:
            'For `Avatar`, use { GitHubAvatar } from @github-ui/github-avatar instead. For `ThemeProvider`, do not use as it causes conflicting styles with SSR.',
        },
        {
          name: '@primer/react/experimental',
          importNames: ['InlineAutocomplete', 'ShowSuggestionsEvent', 'Suggestion'],
          message: 'Use @github-ui/inline-autocomplete instead',
        },
        {
          name: '@primer/react/drafts',
          importNames: ['InlineAutocomplete', 'ShowSuggestionsEvent', 'Suggestion'],
          message: 'Use @github-ui/inline-autocomplete instead',
        },
        {
          name: '@primer/react/experimental',
          importNames: ['MarkdownEditor', 'MarkdownEditorHandle', 'MarkdownEditorProps'],
          message: 'Use @github-ui/comment-box instead',
        },
        {
          name: '@primer/react/drafts',
          importNames: ['MarkdownEditor', 'MarkdownEditorHservandle', 'MarkdownEditorProps'],
          message: 'Use @github-ui/comment-box instead',
        },
        {
          name: '@primer/react/experimental',
          importNames: ['MarkdownViewer'],
          message: 'Use { MarkdownViewer } from @github-ui/markdown-viewer instead',
        },
        {
          name: '@primer/react/drafts',
          importNames: ['MarkdownViewer'],
          message: 'Use { MarkdownViewer } from @github-ui/markdown-viewer instead',
        },
        {
          name: 'react',
          importNames: ['useLayoutEffect'],
          message:
            'Please use the `useLayoutEffect` hook from `@github-ui/use-layout-effect` instead. React.useLayoutEffect is not compatible with SSR.',
        },
        {
          name: '@github-ui/toast/ToastContext',
          importNames: ['useToastContext'],
          message:
            'Toasts degrade the overall user experience and are therefore considered a discouraged pattern. Please consider using alternatives as described in: https://www.figma.com/file/yHGQBFKDI3OsRsfx3mMXLn/Expected-a11y-interactions?type=whiteboard&node-id=96-483&t=QSiiBb064ZfsYhy2-4. If you have any questions, reach out in #primer.',
        },
        {
          name: 'lodash',
          message: 'Use lodash-es instead of lodash',
        },
        {
          name: 'lodash-es',
          message:
            "Don't import the full lodash-es module. Import each function you are using separately with import <function> from 'lodash-es/<function>'",
        },
        {
          name: 'clsx',
          importNames: ['default'],
          message: 'Use the named import instead: `import {clsx} from "clsx"`',
        },
        {
          name: '@github-ui/relay-route',
          message: 'RelayRoute is deprecated. Avoid using it for new code.',
        },
      ],
      patterns: [
        {
          group: ['**/behaviors/**', '**/github/**', '**/marketing/**'],
          message:
            'Please do not import legacy modules into React code as they are not guaranteed to work in SSR. See https://thehub.github.com/epd/engineering/dev-practicals/frontend/react/ssr/ssr-tools/#how-to-fix-no-restricted-imports-errors',
        },
        {
          group: ['*.server'],
          message:
            'Please do not import server modules directly. These will be swapped in during compilation of the alloy bundle. See https://thehub.github.com/epd/engineering/dev-practicals/frontend/react/ssr/ssr-tools/#server-aliases',
        },
        {
          group: [
            '**/hyperlist-web/**',
            '**/inbox/**',
            '**/blackbird-monolith/**',
            '**/repositories/**',
            '**/pull-requests/**',
            '**/react-code-view/**',
            '**/repo-creation/**',
            '**/secret-scanning/**',
            '**/settings/notifications/**',
            '**/settings/rules/**',
            '**/virtual-network-settings/**',
          ],
          message: 'Please do not import react apps modules in react-shared',
        },
        {
          group: ['**/ui/packages/**'],
          message:
            'Please do not import packages directly. Instead install the package in your workspace as a dependency and import from `@github/<package-name>`',
        },
        {
          group: ['**/use-hydrated-effect'],
          message:
            'Prefer `useClientValue` from `@github-ui/use-client-value` or `useLayoutEffect` from React. This hook exists to support an optimization to avoid unnecessary re-paints after hydration and should not be used to measure DOM elements or other browser-only values.',
        },
        {
          group: ['@github-ui/render-phase-provider'],
          importNames: ['useRenderPhase'],
          message:
            "Please use `useClientValue` instead. You can think of `useRenderPhase` as 'environment sniffing' vs `useClientValue`'s 'feature detection' approach.",
        },
      ],
    },
  ],
}

/**
 * @type {import('eslint').Linter.Config}
 */
module.exports.baseConfig = {
  parser: '@typescript-eslint/parser',
  plugins: [
    '@typescript-eslint',
    'compat',
    'delegated-events',
    'filenames',
    'i18n-text',
    'escompat',
    'import',
    'github',
    'custom-elements',
    'jsx-a11y',
    'ssr-friendly',
    'testing-library',
    'relay',
    '@github-ui/dotcom-primer',
    '@github-ui/github-monorepo',
    '@github-ui/ui-commands',
    '@tanstack/query',
    'unicorn',
    'no-barrel-files',
    'clsx',
    'unused-imports',
    '@eslint-react/eslint-plugin',
    'react-compiler',
    'react-google-translate',
  ],
  extends: [
    'plugin:github/internal',
    'plugin:github/recommended',
    'plugin:github/browser',
    'plugin:escompat/typescript',
    'plugin:github/typescript',
    'plugin:import/typescript',
    'plugin:custom-elements/recommended',
    'plugin:react/recommended',
    'plugin:react/jsx-runtime',
    'plugin:react-hooks/recommended',
    'plugin:@tanstack/eslint-plugin-query/recommended',
    // Maintain this order for primer-react/recommended, jsx-a11y/recommended, and github/react
    'plugin:jsx-a11y/recommended',
    'plugin:primer-react/recommended',
    'plugin:github/react',
    'plugin:@github-ui/github-monorepo/react',
    'plugin:relay/strict',
    'plugin:@github-ui/ui-commands/recommended',
    'plugin:@github-ui/dotcom-primer/recommended',
    'plugin:clsx/recommended',
  ],
  parserOptions: {
    project: ['tsconfig.json'],
  },
  ignorePatterns: ['*__generated__*', '**/*.module.css.d.ts'],
  rules: {
    'react-google-translate/no-conditional-text-nodes-with-siblings': 'error',
    'react-google-translate/no-return-text-nodes': 'error',
    'react-compiler/react-compiler': 'error',
    'primer-react/a11y-link-in-text-block': 'error',
    'primer-react/a11y-use-next-tooltip': 'off',
    'no-barrel-files/no-barrel-files': 'error',
    'no-throw-literal': 'error',
    'no-restricted-globals': 'error',
    // we are not using flow types
    'relay/generated-flow-types': 'off',
    'import/no-unresolved': ['error', {ignore: ['^plugin:.*']}],
    'import/extensions': [
      'error',
      'ignorePackages',
      {json: 'always', ts: 'never', tsx: 'never', js: 'never', jsx: 'never'},
    ],
    'custom-elements/extends-correct-class': 'off',
    'custom-elements/one-element-per-file': 'off',
    'custom-elements/define-tag-after-class-definition': 'off',
    'custom-elements/expose-class-on-global': 'off',
    'custom-elements/tag-name-matches-class': ['error', {suffix: ['Element']}],
    'custom-elements/file-name-matches-element': 'off',
    'compat/compat': ['error'],
    'delegated-events/global-on': ['error'],
    'delegated-events/no-high-freq': ['error'],
    'escompat/no-dynamic-imports': 'off',
    'escompat/no-nullish-coalescing': 'off',
    '@typescript-eslint/no-shadow': 'error',
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
    'no-restricted-syntax': [
      'error',
      {
        selector: "NewExpression[callee.name='URL'][arguments.length=1]",
        message: 'Please pass in `window.location.origin` as the 2nd argument to `new URL()`',
      },
      {
        selector: "CallExpression[callee.name='unsafeHTML']",
        message: 'Use unsafeHTML sparingly. Please add an eslint-disable comment if you want to use this',
      },
      {
        selector: "CallExpression[callee.name='readInlineData']",
        message:
          'Avoid using readInlineData. Please add an eslint-disable comment if you have to use this. See https://thehub.github.com/support/ecosystem/api-graphql/training/relay/relay-read-inline-data/',
      },
    ],
    'no-restricted-imports': [
      'error',
      {
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
            name: '@github-ui/failbot',
            importNames: ['reportError'],
            message:
              'Calling `reportError` directly is deprecated. To report errors to sentry, let them bubble to the document naturally or re-throw them. If they get caught by calling code you wish to avoid, wrap the re-throw in a setTimeout.',
          },
          {
            name: '@github/selector-observer',
            message:
              'Use a Catalyst component instead of observing an element. See https://thehub.github.com/epd/engineering/dev-practicals/frontend/client-side-behaviors-with-catalyst/',
          },
          {
            name: 'delegated-events',
            message:
              "Use a Catalyst component instead of listening to an element's events. See https://thehub.github.com/epd/engineering/dev-practicals/frontend/client-side-behaviors-with-catalyst/",
          },
          {
            name: '@github/hotkey',
            message: 'Please import from @github-ui/hotkey instead',
          },
          {
            name: '@github/jtml',
            message: 'Use the shimmed version of jtml instead. See @github-ui/jtml-shimmed',
          },
          {
            name: '@primer/react',
            importNames: ['Avatar'],
            message: 'Use { GitHubAvatar } from @github-ui/github-avatar instead',
          },
          {
            name: '@testing-library/user-event',
            message:
              'Avoid importing user-event directly. Instead, use `render` (and unpack `user` from the result) or `setupUserEvent` from "@github-ui/react-core/test-utils".',
          },
          {
            name: 'lodash',
            message: 'Use lodash-es instead of lodash',
          },
          {
            name: 'lodash-es',
            message:
              "Don't import the full lodash-es module. Import each function you are using separately with import <function> from 'lodash-es/<function>'",
          },
          {
            name: '@github-ui/relay-route',
            message: 'RelayRoute is deprecated. Avoid using it for new code.',
          },
        ],
        patterns: [
          {
            group: ['*.server'],
            message:
              'Please do not import server modules directly. These will be swapped in during compilation. See https://thehub.github.com/epd/engineering/dev-practicals/frontend/react/ssr/',
          },
        ],
      },
    ],
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
  },
  settings: {
    polyfills: ['Request', 'window.customElements', 'window.requestIdleCallback'],
    'import/parsers': {
      '@typescript-eslint/parser': ['.ts', '.tsx'],
    },
    'import/resolver': {
      typescript: true,
      node: {
        extensions: ['.js', '.ts', '.tsx'],
        moduleDirectory: ['node_modules', 'app/assets/modules'],
      },
    },
    react: {
      version: 'detect',
    },
  },
  overrides: [
    {
      files: ['*.ts?(x)'],
      extends: ['plugin:@eslint-react/recommended-type-checked-legacy'],
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
      files: ['*.json'],
      rules: {
        'filenames/match-regex': 'off',
        '@typescript-eslint/no-unused-expressions': 'off',
      },
      parser: undefined,
      parserOptions: {
        project: null,
      },
    },
    {
      files: ['package.json'],
      extends: ['plugin:@github-ui/github-monorepo/package-json'],
      parser: undefined,
      parserOptions: {
        project: null,
      },
    },
    {
      files: ['*.d.ts'],
      rules: {
        '@typescript-eslint/no-unused-vars': 'off',
        'no-var': 'off',
      },
    },
    {
      files: ['*.stories.tsx', '*.stories.ts'],
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
      files: ['**/__browser-tests__/**/*.ts'],
      extends: ['plugin:@github-ui/github-monorepo/test'],
      rules: {
        'no-throw-literal': 'off',
        '@typescript-eslint/only-throw-error': 'error',
        'filenames/match-regex': 'off',
        '@typescript-eslint/no-non-null-assertion': ['off'],
        '@github-ui/github-monorepo/test-file-names': 'error',
        'react-compiler/react-compiler': 'error',
      },
    },
    {
      files: ['**/__tests__/**/*.tsx', '**/__tests__/**/*.ts'],
      plugins: ['jest'],
      extends: ['plugin:jest/recommended', 'plugin:testing-library/react', 'plugin:@github-ui/github-monorepo/test'],
      rules: {
        'no-throw-literal': 'off',
        '@typescript-eslint/only-throw-error': 'error',
        'i18n-text/no-en': 'off',
        'github/unescaped-html-literal': 'off',
        'filenames/match-regex': 'off',
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
      files: ['*.config.js', '*.config.mjs', 'test/linting/*.js', 'janky-reporter.mjs', 'janky-formatter.js'],
      extends: ['plugin:github/internal', 'plugin:escompat/typescript'],
      parser: undefined,
      parserOptions: {
        project: null,
      },
      env: {
        node: true,
        browser: false,
      },
      globals: {
        process: true,
        __dirname: true,
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
      files: ['eslintrc.js', '.eslintrc.js'],
      parser: undefined,
      parserOptions: {
        project: null,
      },
      env: {
        node: true,
        browser: false,
      },
      rules: {
        'filenames/match-regex': ['off'],
        'import/no-commonjs': ['off'],
      },
    },
  ],
}
