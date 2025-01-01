import {RuleTester} from 'eslint'
import rule from '../require-ui-test-utilities'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('require-ui-test-utilities', rule as any, {
  valid: [
    {
      // Valid test file with correct utilities
      code: `
        vi.fn()
        describe('Test suite', () => {
          it('should work', () => {
            expect(true).toBe(true)
          })
        })
      `,
      filename: 'example.browser.test.ts',
    },
    {
      // Non-test file should not trigger the rule
      code: `
        jest.fn()
        describe('Test suite', () => {
          test('should work', () => {
            expect(true).toBe(true)
          })
        })
      `,
      filename: 'example.js',
    },
    {
      // Code that doesn't include restricted utilities
      code: `
        window.history.pushState({}, '', url.toString())
      `,
      filename: 'example.browser.test.ts',
    },
  ],

  invalid: [
    {
      // Replace `jest` with `vi`
      code: `
        jest.fn()
        describe('Test suite', () => {
          it('should work', () => {
            expect(true).toBe(true)
          })
        })
      `,
      filename: 'example.browser.test.ts',
      errors: [{messageId: 'replaceTestUtility', data: {original: 'jest', replacement: 'vi'}}],
      output: `
        vi.fn()
        describe('Test suite', () => {
          it('should work', () => {
            expect(true).toBe(true)
          })
        })
      `,
    },
    {
      // Replace `test` with `it`
      code: `
        test('should work', () => {
          expect(true).toBe(true)
        })
      `,
      filename: 'example.server.test.ts',
      errors: [{messageId: 'replaceTestUtility', data: {original: 'test', replacement: 'it'}}],
      output: `
        it('should work', () => {
          expect(true).toBe(true)
        })
      `,
    },
    {
      // Replace both `jest` and `test`
      code: `
        jest.fn()
        test('should work', () => {
          expect(true).toBe(true)
        })
      `,
      filename: 'example.browser.test.ts',
      errors: [
        {messageId: 'replaceTestUtility', data: {original: 'jest', replacement: 'vi'}},
        {messageId: 'replaceTestUtility', data: {original: 'test', replacement: 'it'}},
      ],
      output: `
        vi.fn()
        it('should work', () => {
          expect(true).toBe(true)
        })
      `,
    },
  ],
})
