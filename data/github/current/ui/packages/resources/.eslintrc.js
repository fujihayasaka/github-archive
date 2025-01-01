// @ts-check

/** @type {import('eslint').Linter.Config} */
module.exports = {
  rules: {
    'primer-react/no-system-props': 'off',
    'no-barrel-files/no-barrel-files': 'off',
    '@typescript-eslint/no-non-null-assertion': 'off',
    'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
    'react-google-translate/no-return-text-nodes': 'off',
  },
  overrides: [
    {
      files: ['./lib/types/contentful/contentTypes/*.ts', './layouts/**/*.tsx'],
      rules: {
        /**
         * We name these files following their Content Type "id" in Contentful, e.g. "primerComponentHero".
         */
        'filenames/match-regex': 'off',
      },
    },
  ],
}
