import eslint from '@eslint/js'
import {defaultConfig} from '@github-ui/eslintrc'
import relay from 'eslint-plugin-relay'
import simpleImportSort from 'eslint-plugin-simple-import-sort'
import tseslint, {configs} from 'typescript-eslint'

const typeScriptConfig = tseslint.config({
  files: ['**/*.ts', '**/*.tsx'],
  extends: [eslint.configs.recommended, configs.recommendedTypeChecked],
  languageOptions: {
    parserOptions: {
      tsconfigRootDir: import.meta.dirname,
      project: './tsconfig.json',
    },
  },
  rules: {
    '@typescript-eslint/no-non-null-assertion': ['off'],
  },
})

export default [
  ...defaultConfig,
  ...typeScriptConfig,
  relay.configs.strict,
  {
    ignores: ['tsconfig.json', 'jest.config.js', 'package.json'],
    plugins: {
      'simple-import-sort': simpleImportSort,
    },
    rules: {
      'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
      'react-google-translate/no-return-text-nodes': 'off',
      'no-barrel-files/no-barrel-files': 'off',
      camelcase: 'off',
      'simple-import-sort/imports': 'error',
      'simple-import-sort/exports': 'error',
      'import/newline-after-import': 'error',
      'import/no-deprecated': 'warn',
      'sort-imports': 'off',
      'relay/generated-flow-types': 'off',
      'react/jsx-sort-props': [
        'error',
        {
          reservedFirst: true,
          shorthandFirst: true,
          callbacksLast: true,
          multiline: 'last',
          ignoreCase: false,
        },
      ],
      '@github-ui/github-monorepo/no-sx': 'off',
    },
  },
  {
    files: ['**/__tests__/*'],
    rules: {
      '@typescript-eslint/no-non-null-assertion': ['off'],
    },
  },
]
