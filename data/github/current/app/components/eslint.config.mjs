// @ts-check
import {legacyConfig} from '@github-ui/eslintrc/legacy'

export default [
  ...legacyConfig,
  {
    rules: {
      // temporary disable to incrementally remove barrel files
      'no-barrel-files/no-barrel-files': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@github-ui/github-monorepo/migrated-package-imports': 'error',
    },
  },
  {
    files: ['**/*.ts'],
    rules: {
      'ssr-friendly/no-dom-globals-in-module-scope': 'off',
      'ssr-friendly/no-dom-globals-in-constructor': 'off',
      'ssr-friendly/no-dom-globals-in-react-cc-render': 'off',
      'ssr-friendly/no-dom-globals-in-react-fc': 'off',
      'no-restricted-imports': 'off',
    },
  },
  {
    files: ['search/**/*'],
    rules: {
      '@typescript-eslint/no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: ['**/parsing/parsing'],
              message:
                'Do not import parsing/parsing, this will likely break delayed loading. Use import type instead.',
              allowTypeImports: true,
            },
            {
              group: ['@github/blackbird-parser'],
              message:
                'Do not import blackbird-parser, this will likely break delayed loading. Use import type instead.',
              allowTypeImports: true,
            },
          ],
          paths: [
            {
              name: '@github-ui/failbot',
              importNames: ['reportError'],
              message:
                'Calling `reportError` directly is deprecated. To report errors to sentry, let them bubble to the document naturally or re-throw them. If they get caught by calling code you wish to avoid, wrap the re-throw in a setTimeout.',
            },
          ],
        },
      ],
    },
  },
]
