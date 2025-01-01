import {RuleTester} from '@typescript-eslint/rule-tester'
import rule from '../package-json-ordered-fields'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('check-ordered-fields', rule as any, {
  // tests that use the check ordered fields rule to valid package.json exports
  valid: [
    {
      code: `
{
  "exports": {
    "./alloy-handler": "./file.tsx"
  }
}`,
      filename: 'ui/packages/test/package.json',
    },
    {
      code: `
{
  "exports": {
    "./alloy-handler": "./file.tsx",
    "./ReactAppElement": "./file.tsx"
  }
}`,
      filename: 'ui/packages/test/package.json',
    },
  ],
  invalid: [
    {
      code: `
{
  "exports": {
    "./ReactAppElement": "./file.tsx",
    "./alloy-handler": "./file.tsx"
  }
}`,
      filename: 'ui/packages/test/package.json',
      errors: [
        {
          messageId: 'packageJsonOrderedFields',
        },
      ],
      output: `
{
  "exports": {
    "./alloy-handler": "./file.tsx",
    "./ReactAppElement": "./file.tsx"
  }
}`,
    },
  ],
})
