import {RuleTester} from '@typescript-eslint/rule-tester'
import rule from '../no-global-test-helpers'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('no-global-test-helpers', rule as any, {
  valid: [
    {
      code: `
        import {describe, it, beforeEach, before, after, afterEach} from '@github-ui/tests'
        describe('some-description', () => {
          it('some-test', () => {})
          beforeEach(() => {})
          before(() => {})
          after(() => {})
          afterEach(() => {})
        })
      `,
      filename: 'ui/packages/test/some-test-file.test.ts',
    },
    {
      // Ensuring the ESLint CallExpression ignores method calls to matching keywords like `.test`
      code: `
        import {describe, it} from '@github-ui/tests'
        describe('some-description', () => {
          it('some-test', () => {
            assert.isTrue(/some-regex/.test("some-regex string"))
          })
        })
      `,
      filename: 'ui/packages/test/some-test-file.test.ts',
    },
  ],

  invalid: [
    {
      code: `
        suite('some-description', () => {
          test('some-test', () => {})
          setup(() => {})
          suiteSetup(() => {})
          suiteTeardown(() => {})
          teardown(() => {})
        })
      `,
      filename: 'ui/packages/test/some-test-file.test.ts',
      errors: [
        {
          messageId: 'avoidGlobalTestHelpers',
        },
      ],
      output: `
        import {after, afterEach, before, beforeEach, describe, it} from '@github-ui/tests'
describe('some-description', () => {
          it('some-test', () => {})
          beforeEach(() => {})
          before(() => {})
          after(() => {})
          afterEach(() => {})
        })
      `,
    },
    {
      code: `
            import {fixture, html} from '@github-ui/tests'
            suite('some-description', () => {
              test('some-test', () => {})
            })
          `,
      filename: 'ui/packages/test/some-test-file.test.ts',
      errors: [
        {
          messageId: 'avoidGlobalTestHelpers',
        },
      ],
      output: `
            import {describe, fixture, html, it} from '@github-ui/tests'
            describe('some-description', () => {
              it('some-test', () => {})
            })
          `,
    },
  ],
})
