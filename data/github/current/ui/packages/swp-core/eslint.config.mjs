import {defaultConfig} from '@github-ui/eslintrc'

export default [
  ...defaultConfig,
  {
    rules: {
      'primer-react/no-system-props': 'off', // this project uses @primer/react-brand instead of @primer/react
      'react-google-translate/no-conditional-text-nodes-with-siblings': 'off',
      'react-google-translate/no-return-text-nodes': 'off',
      '@github-ui/github-monorepo/no-sx': 'off',
    },
  },
  {
    files: ['schemas/contentful/contentTypes/*.ts'],

    rules: {
      // we name files following their content type "id" in Contentful
      '@github-ui/github-monorepo/filename-convention': 'off',
    },
  },
]
