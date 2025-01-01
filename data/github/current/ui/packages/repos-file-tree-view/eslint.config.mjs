// @ts-check
import {defaultConfig} from '@github-ui/eslintrc'
import {sortImportsConfig} from '@github-ui/eslintrc/configs/sort-imports'

export default [
  ...defaultConfig,
  sortImportsConfig,
  {
    rules: {
      'prettier/prettier': ['error'],
      'no-barrel-files/no-barrel-files': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
      'import/no-deprecated': 'warn',
      '@github-ui/github-monorepo/no-sx': 'off',
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
]
