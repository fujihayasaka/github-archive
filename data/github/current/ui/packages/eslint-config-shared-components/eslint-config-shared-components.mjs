import i18nText from 'eslint-plugin-i18n-text'
import noOnlyTests from 'eslint-plugin-no-only-tests'
import pluginJest from 'eslint-plugin-jest'
import prettier from 'eslint-plugin-prettier'
import simpleImportSort from 'eslint-plugin-simple-import-sort'
import testingLibrary from 'eslint-plugin-testing-library'
import tseslint, {configs, parser, plugin} from 'typescript-eslint'
import {defaultConfig} from '@github-ui/eslintrc'

const reactPlugin = (await import('eslint-plugin-react')).default

const tseConfig = tseslint.config({
  files: ['**/*.ts', '**/*.tsx'],
  extends: [configs.recommendedTypeChecked],
  languageOptions: {
    parser,
    parserOptions: {
      sourceType: 'module',
      project: ['./tsconfig.json'],
      projectService: true,
    },
  },
  rules: {
    '@typescript-eslint/no-floating-promises': ['error'],
    '@typescript-eslint/require-await': ['error'],
    '@typescript-eslint/no-misused-promises': [
      'error',
      {
        checksVoidReturn: {attributes: false},
        checksConditionals: false,
      },
    ],
    '@typescript-eslint/no-unsafe-assignment': ['off'],
    '@typescript-eslint/no-unsafe-member-access': ['off'],
    '@typescript-eslint/no-unused-vars': ['off'], // handled by unused-imports plugin in inherited config
  },
})

export default [
  ...defaultConfig,
  {
    ignores: ['**/coverage/**'],
    plugins: {
      i18nText,
      prettier,
      'simple-import-sort': simpleImportSort,
      '@typescript-eslint': plugin,
    },
    rules: {
      'prettier/prettier': ['error'],
      camelcase: 'error',
      'simple-import-sort/imports': 'error',
      'simple-import-sort/exports': 'error',
      'i18n-text/no-en': 'off',
      'import/first': 'error',
      'import/newline-after-import': 'error',
      'import/no-duplicates': 'error',
      'import/no-deprecated': 'warn',
      'sort-imports': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },
  ...tseConfig,
  {
    files: ['**/*.ts', '**/*.tsx'],
    plugins: {
      i18nText,
    },
    rules: {
      'i18n-text/no-en': 'off',
    },
  },
  {
    ...testingLibrary.configs['flat/react'],
    ...pluginJest.configs['flat/recommended'],
    files: ['**/__tests__/**'],
    plugins: {
      jest: pluginJest,
      i18nText,
      '@typescript-eslint': plugin,
      'no-only-tests': noOnlyTests,
      react: reactPlugin,
      'testing-library': testingLibrary,
    },
    rules: {
      'github/unescaped-html-literal': 0,
      'no-restricted-imports': 'off',
      // reject any usages of .only() in tests as we want all tests to run on CI
      'no-only-tests/no-only-tests': process.env.CI ? 'error' : 'warn',

      // enforcing this so that our tests are properly handling promises
      '@typescript-eslint/no-floating-promises': ['error'],

      // coding style rules that we could re-enable later
      '@typescript-eslint/no-non-null-assertion': ['off'],
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
      // rules for test authoring and formatting
      'jest/no-conditional-expect': 'off',
      'jest/consistent-test-it': ['error', {fn: 'it', withinDescribe: 'it'}],
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
    },
  },
  {
    files: ['**/*.stories.tsx', '**/__tests__/utils/*.tsx'],
    plugins: {
      'testing-library': testingLibrary,
    },
    rules: {
      // Storybook tests use `canvas` instead of `screen`
      'testing-library/prefer-screen-queries': ['off'],
    },
  },
]
