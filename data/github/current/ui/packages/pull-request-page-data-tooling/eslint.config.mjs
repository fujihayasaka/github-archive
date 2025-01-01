import eslint from '@eslint/js'
import {defaultConfig} from '@github-ui/eslintrc'
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
  {
    ignores: ['tsconfig.json', 'jest.config.js', 'package.json'],
    plugins: {
      'simple-import-sort': simpleImportSort,
    },
    rules: {
      'no-barrel-files/no-barrel-files': 'off',
      camelcase: 'off',
      'simple-import-sort/imports': 'error',
      'simple-import-sort/exports': 'error',
      'import/newline-after-import': 'error',
      'import/no-deprecated': 'warn',
      'sort-imports': 'off',
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
    },
  },
  {
    files: ['**/__tests__/*'],
    rules: {
      '@typescript-eslint/no-non-null-assertion': ['off'],
    },
  },
]
