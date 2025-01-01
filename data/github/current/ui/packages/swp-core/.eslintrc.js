// @ts-check

/** @type {import('eslint').Linter.Config} */
module.exports = {
  rules: {
    'primer-react/no-system-props': 'off', // this project uses @primer/react-brand instead of @primer/react
    'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
    'react-google-translate/no-return-text-nodes': 'off',
  },

  overrides: [
    {
      files: ['./schemas/contentful/contentTypes/*.ts'],

      rules: {
        'filenames/match-regex': 'off', // we name files following their content type "id" in Contentful
      },
    },
  ],
}
