// This is an eslint configuration for build-time scripts. It should not be used any any code that is built into a
// browser bundle. If you are using this configuration, you probably also want to set your package.json's `dev` to
// true.
import globals from 'globals'
import i18nText from 'eslint-plugin-i18n-text'
import {plugin} from 'typescript-eslint'
import {defaultConfig} from './eslint-default.mjs'

export default [
  ...defaultConfig,
  {
    languageOptions: {
      globals: {
        ...globals.node,
      },
    },
    plugins: {
      i18nText,
    },
    rules: {
      'i18n-text/no-en': 'off',
      'import/no-nodejs-modules': 'off',
      'no-console': 'off',
      'import/extensions': [
        'error',
        'ignorePackages',
        // allow extensions for esm imports
        {json: 'always', ts: 'allow', tsx: 'allow', js: 'allow', jsx: 'allow'},
      ],
    },
  },
  {
    files: ['**/*.js'],
    languageOptions: {
      parserOptions: {
        project: null,
      },
    },
    plugins: {
      '@typescript-eslint': plugin,
    },
    rules: {
      '@typescript-eslint/no-var-requires': 'off',
      '@typescript-eslint/no-require-imports': 'off',
      'import/no-commonjs': 'off',
    },
  },
]
