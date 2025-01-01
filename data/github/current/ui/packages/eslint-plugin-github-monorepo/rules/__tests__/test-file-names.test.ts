import {RuleTester} from '@typescript-eslint/rule-tester'
import rule from '../test-file-names'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('test-file-names', rule as any, {
  valid: [
    // Proper test file name with `.ts`
    {
      code: `
        describe('some-description', () => {
          test('some-test', () => {})
        })
      `,
      filename: 'ui/packages/test/__test__/some-description.test.ts',
    },
    // Proper test file name with `.tsx`
    {
      code: `
        describe('some-description', () => {
          test('some-test', () => {})
        })
      `,
      filename: 'ui/packages/test/__test__/some-description.test.tsx',
    },
    // Skip validation if there is an import from @github-ui/tests
    {
      code: `
        import { someFunction } from '@github-ui/tests';
        describe('some-description', () => {
          test('some-test', () => {})
        })
      `,
      filename: 'ui/packages/test/__test__/some-description.invalid.ts',
    },
  ],

  invalid: [
    // Typo'd test file
    {
      code: `
      describe('some-description', () => {
        test('some-test', () => {})
      })
        `,
      errors: [
        {
          messageId: 'testFileNames',
        },
        {
          messageId: 'testFileNames',
        },
      ],

      filename: 'ui/packages/test/__test__/some-description.1test.ts',
    },
    // non test file
    {
      code: `
      describe('some-description', () => {
        test('some-test', () => {})
      })
        `,
      errors: [
        {
          messageId: 'testFileNames',
        },
        {
          messageId: 'testFileNames',
        },
      ],

      filename: 'ui/packages/test/__test__/some-description.ts',
    },
  ],
})
