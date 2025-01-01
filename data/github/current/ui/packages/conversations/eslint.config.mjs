// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'
import {sortImportsConfig} from '@github-ui/eslintrc/configs/sort-imports'

export default [
  ...defaultConfig,
  sortImportsConfig,
  {
    rules: {
      'no-barrel-files/no-barrel-files': 'off',
      camelcase: 'off',
      'import/no-deprecated': 'warn',
      '@typescript-eslint/no-non-null-assertion': 'off',
      'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
      'react-google-translate/no-return-text-nodes': 'off',
      '@github-ui/github-monorepo/no-sx': 'off',
    },
    settings: {
      'import/resolver': {
        node: {
          extensions: ['.js', '.ts', '.tsx'],
        },
        typescript: true,
      },
    },
  },
  {
    files: ['**/__tests__/*'],
    rules: {
      'github/unescaped-html-literal': 0,
    },
  },
  {
    files: ['emojis.ts'],
    rules: {
      camelcase: 'off',
    },
  },
]
