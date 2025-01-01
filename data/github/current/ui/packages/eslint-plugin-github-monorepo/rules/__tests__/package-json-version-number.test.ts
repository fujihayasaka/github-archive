import {AST_NODE_TYPES} from '@typescript-eslint/utils'
import {RuleTester} from '@typescript-eslint/rule-tester'

import rule from '../package-json-version-numbers'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('check-version-numbers', rule as any, {
  valid: [
    // Internal dependencies
    {
      code: `
        {
          "dependencies": {
            "@github-ui/foo": "*"
          },
          "devDependencies": {
            "@github-ui/bar": "*"
          }
        }
      `,
      filename: 'ui/packages/test/package.json',
    },
    // Managed dependencies
    {
      code: `
        {
          "dependencies": {
            "react": "*"
          },
          "devDependencies": {
            "@testing-library/react": "*"
          }
        }
      `,
      filename: 'ui/packages/test/package.json',
    },
    // Managed dependencies, in owning package
    {
      code: `
        {
          "dependencies": {
            "react": "18.0.0"
          },
          "devDependencies": {
            "@testing-library/react": "1.2.3"
          }
        }
      `,
      filename: 'ui/packages/react-core/package.json',
    },
    // Exempt dependencies
    {
      code: `
        {
          "dependencies": {
            "react": "19.0.0",
            "react-dom": "19.0.0"
          }
        }
      `,
      filename: 'ui/packages/react-next/package.json',
    },
  ],

  invalid: [
    // External dependencies
    {
      code: `
        {
          "dependencies": {
            "foo": "*"
          }
        }
        `,
      errors: [
        {
          messageId: 'packageJsonVersionNumbers',
          type: AST_NODE_TYPES.Literal,
        },
      ],

      filename: 'ui/packages/test/package.json',
    },

    // Managed dependencies, in non-owning package
    {
      code: `
        {
          "dependencies": {
            "react": "18.0.0"
          }
        }
      `,
      output: `
        {
          "dependencies": {
            "react": "*"
          }
        }
      `,
      errors: [
        {
          messageId: 'packageJsonVersionNumbers',
          type: AST_NODE_TYPES.Literal,
        },
      ],
      filename: 'ui/packages/other/package.json',
    },

    // Managed dependencies, in owning package
    {
      code: `
        {
          "dependencies": {
            "react": "*"
          }
        }
      `,
      errors: [
        {
          messageId: 'packageJsonVersionNumbers',
          type: AST_NODE_TYPES.Literal,
        },
      ],
      filename: 'ui/packages/react-core/package.json',
    },

    // Internal dependencies
    {
      code: `
        {
          "devDependencies": {
            "@github-ui/foo": "18.0.0"
          }
        }
      `,
      output: `
        {
          "devDependencies": {
            "@github-ui/foo": "*"
          }
        }
      `,
      errors: [
        {
          messageId: 'packageJsonVersionNumbers',
          type: AST_NODE_TYPES.Literal,
        },
      ],
      filename: 'ui/packages/bar/package.json',
    },
  ],
})
