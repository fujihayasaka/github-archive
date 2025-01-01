// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'
import {sortImportsConfig} from '@github-ui/eslintrc/configs/sort-imports'
import pluginJest from 'eslint-plugin-jest'
import testingLibrary from 'eslint-plugin-testing-library'
import tseslint, {configs, parser} from 'typescript-eslint'

const tseConfig = tseslint.config({
  files: ['**/*.ts', '**/*.tsx'],
  extends: [configs.recommendedTypeChecked],
  languageOptions: {
    parser,
    parserOptions: {
      sourceType: 'module',
      tsconfigRootDir: import.meta.dirname,
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
  },
})

export default [
  ...defaultConfig,
  sortImportsConfig,
  {
    rules: {
      'prettier/prettier': ['error'],
      camelcase: 'error',
      'import/no-duplicates': 'error',
      'import/no-deprecated': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
      'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
      'react-google-translate/no-return-text-nodes': 'off',
      '@github-ui/github-monorepo/no-sx': 'off',
      '@github-ui/github-monorepo/prefer-data-router': 'off',
      '@github-ui/github-monorepo/restrict-relay-imports': 'off',
    },
    settings: {
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
  ...tseConfig,
  {
    ...testingLibrary.configs['flat/react'],
    ...pluginJest.configs['flat/recommended'],
    files: ['**/*.ts', '**/*.tsx'],
    rules: {
      'i18n-text/no-en': 'off',
      '@github-ui/ui-commands/no-manual-shortcut-logic': 'off',
    },
  },
  {
    files: ['**/__tests__/**'],
    rules: {
      'github/unescaped-html-literal': 0,
      'no-restricted-imports': 'off',
      '@typescript-eslint/no-unsafe-return': 'off',
    },
  },
  {
    files: ['**/copilot-chat-service.ts'],
    rules: {
      camelcase: 'off',
    },
  },
  {
    files: ['eslint.config.mjs'],
    rules: {
      // muting any warning about upgrading to ES Modules for now
      'import/no-commonjs': ['off'],
      'no-restricted-imports': ['off'],
      'import/no-extraneous-dependencies': ['off'],
      '@typescript-eslint/no-var-requires': ['off'],
    },
  },
]
