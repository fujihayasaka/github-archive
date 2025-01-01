import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      'primer-react/no-system-props': 'off',
      'no-barrel-files/no-barrel-files': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },
  {
    files: ['lib/types/contentful/contentTypes/**/*.ts', './layouts/**/*.tsx'],
    rules: {
      /**
       * We name these files following their Content Type "id" in Contentful, e.g. "primerComponentHero".
       */
      '@github-ui/github-monorepo/filename-convention': 'off',
    },
  },
]
