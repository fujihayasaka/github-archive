import {RuleTester} from '@typescript-eslint/rule-tester'
import rule from '../react-app-name'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('react-app-package-name-rule', rule as any, {
  valid: [
    // Valid: registerNavigatorApp matches the package name
    {
      code: `
        registerNavigatorApp('my-app')
      `,
      filename: '/ui/packages/my-app/index.js',
    },

    // Valid: DataRouterApplicationBuilder.create matches the package name
    {
      code: `
        DataRouterApplicationBuilder.create('my-app')
      `,
      filename: '/ui/packages/my-app/index.js',
    },

    // Valid: Non-matching calls are ignored
    {
      code: `
        someOtherFunction('not-my-app')
      `,
      filename: '/ui/packages/not-my-app/index.js',
    },
  ],

  invalid: [
    // Invalid: registerNavigatorApp does not match the package name
    {
      code: `registerNavigatorApp('wrong-app')`,
      filename: '/ui/packages/my-app/index.js',
      errors: [
        {
          suggestions: [
            {
              messageId: 'suggestionMessage',
              output: `registerNavigatorApp('my-app')`,
            },
          ],
          messageId: 'reactAppName',
        },
      ],
    },

    // Invalid: DataRouterApplicationBuilder.create does not match the package name
    {
      code: `DataRouterApplicationBuilder.create('wrong-app')`,
      filename: '/ui/packages/my-app/index.js',
      errors: [
        {
          suggestions: [
            {
              messageId: 'suggestionMessage',
              output: `DataRouterApplicationBuilder.create('my-app')`,
            },
          ],
          messageId: 'reactAppName',
        },
      ],
    },

    // Invalid: registerNavigatorApp with no arguments
    {
      code: `registerNavigatorApp('')`,
      filename: '/ui/packages/my-app/index.js',
      errors: [
        {
          suggestions: [
            {
              messageId: 'suggestionMessage',
              output: `registerNavigatorApp('my-app')`,
            },
          ],
          messageId: 'reactAppName',
        },
      ],
    },

    // Invalid: DataRouterApplicationBuilder.create with no arguments
    {
      code: `DataRouterApplicationBuilder.create('')`,
      filename: '/ui/packages/my-app/index.js',
      errors: [
        {
          suggestions: [
            {
              messageId: 'suggestionMessage',
              output: `DataRouterApplicationBuilder.create('my-app')`,
            },
          ],
          messageId: 'reactAppName',
        },
      ],
    },
  ],
})
