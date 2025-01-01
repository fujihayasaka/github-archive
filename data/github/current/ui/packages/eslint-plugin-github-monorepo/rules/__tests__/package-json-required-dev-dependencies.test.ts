import {RuleTester} from '@typescript-eslint/rule-tester'

import rule from '../package-json-required-dev-dependencies'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('package-json-required-dev-dependencies', rule as any, {
  valid: [
    {
      code: `
        {
          "devDependencies": {
            "@github-ui/eslintrc": "*",
            "@github-ui/jest": "*"
          }
        }
      `,
      filename: 'ui/packages/test/package.json',
    },
    {
      code: `
        {
          "devDependencies": {
            "@github-ui/eslintrc": "*",
            "@github-ui/tests": "*"
          }
        }
      `,
      filename: 'ui/packages/test/package.json',
    },
    {
      code: `
        {
          "devDependencies": {
            "@github-ui/eslintrc": "*",
            "@github-ui/jest": "*",
            "@github-ui/tests": "*"
          }
        }
      `,
      filename: 'ui/packages/ui-packages-tooling/package.json',
    },
  ],

  invalid: [
    // must include a test dependency
    {
      code: `{
              "devDependencies": {
                "@github-ui/eslintrc": "*"
              }
            }`,
      errors: [
        {
          messageId: 'missingDependenciesMessage',
          data: {devDependency: '@github-ui/tests'},
        },
      ],
      filename: 'ui/packages/other/package.json',
      output: `{
    "devDependencies": {
      "@github-ui/eslintrc": "*",
      "@github-ui/tests": "*"
    }
  }`,
    },
    // must include required dependency
    {
      code: `
        {
          "devDependencies": {
            "@github-ui/jest": "*"
          }
        }
      `,
      errors: [
        {
          messageId: 'missingDependenciesMessage',
          data: {devDependency: '@github-ui/eslintrc'},
        },
      ],
      filename: 'ui/packages/test/package.json',
      output: `
        {
    "devDependencies": {
      "@github-ui/eslintrc": "*",
      "@github-ui/jest": "*"
    }
  }`,
    },
    // must include required dependency
    {
      code: `
        {
          "devDependencies": {
            "@github-ui/tests": "*"
          }
        }
      `,
      errors: [
        {
          messageId: 'missingDependenciesMessage',
          data: {devDependency: '@github-ui/eslintrc'},
        },
      ],
      filename: 'ui/packages/test/package.json',
      output: `
        {
    "devDependencies": {
      "@github-ui/eslintrc": "*",
      "@github-ui/tests": "*"
    }
  }`,
    },
    // must include required dependency and one test dependency
    {
      code: `
        {
          "devDependencies": {
            "@github-ui/managed-dependencies": "*"
          }
        }
      `,
      errors: [
        {
          messageId: 'missingDependenciesMessage',
          data: {devDependency: '@github-ui/eslintrc, @github-ui/tests'},
        },
      ],
      filename: 'ui/packages/test/package.json',
      output: `
        {
    "devDependencies": {
      "@github-ui/eslintrc": "*",
      "@github-ui/managed-dependencies": "*",
      "@github-ui/tests": "*"
    }
  }`,
    },
    // cannot include more than one test dependency
    {
      code: `
        {
          "devDependencies": {
            "@github-ui/eslintrc": "*",
            "@github-ui/jest": "*",
            "@github-ui/tests": "*"
          }
        }
      `,
      errors: [
        {
          messageId: 'extraTestDependencyMessage',
        },
      ],
      filename: 'ui/packages/test/package.json',
      output: `
        {
    "devDependencies": {
      "@github-ui/eslintrc": "*",
      "@github-ui/tests": "*"
    }
  }`,
    },
  ],
})
