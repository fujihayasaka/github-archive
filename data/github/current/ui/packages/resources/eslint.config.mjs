import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      'primer-react/no-system-props': 'off',
      'no-barrel-files/no-barrel-files': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
      'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
      'react-google-translate/no-return-text-nodes': 'off',
    },
  },
  {
    files: ['lib/types/contentful/contentTypes/*.ts', './layouts/**/*.tsx'],
    rules: {
      /**
       * We name these files following their Content Type "id" in Contentful, e.g. "primerComponentHero".
       */
      '@github-ui/github-monorepo/filename-convention': 'off',
    },
  },
]
