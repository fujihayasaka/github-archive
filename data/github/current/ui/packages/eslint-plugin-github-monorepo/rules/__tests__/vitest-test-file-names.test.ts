import {RuleTester} from '@typescript-eslint/rule-tester'
import rule from '../vitest-test-file-names'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('vitest-test-file-names', rule as any, {
  valid: [
    // Proper browser test file with .ts
    {
      code: `
        import {it, expect} from '@github-ui/tests'
        it('some-test', () => {})
      `,
      filename: 'ui/packages/test/__test__/component.browser.test.ts',
    },
    // Proper server test file with .tsx
    {
      code: `
        import {it, expect} from '@github-ui/tests'
        it('some-test', () => {})
      `,
      filename: 'ui/packages/test/__test__/api.server.test.tsx',
    },
    // Proper jsdom test file with .tsx
    {
      code: `
        import {it, expect} from '@github-ui/tests'
        it('some-test', () => {})
      `,
      filename: 'ui/packages/test/__test__/utils.jsdom.test.tsx',
    },
    // File with correct pattern using the browser import
    {
      code: `
        import {it, expect} from '@github-ui/tests/browser'
        it('some-test', () => {})
      `,
      filename: 'ui/packages/test/__test__/component.browser.test.ts',
    },
    // Non-Vitest test file (no relevant imports)
    {
      code: `
        import {describe, it} from 'jest'
        describe('some-description', () => {
          it('some-test', () => {})
        })
      `,
      filename: 'ui/packages/test/__test__/some-component.test.ts',
    },
  ],

  invalid: [
    // Vitest import but incorrect file pattern (missing browser|server|jsdom)
    {
      code: `
        import {it, expect} from '@github-ui/tests'
        it('some-test', () => {})
      `,
      errors: [
        {
          messageId: 'vitestFileNames',
        },
      ],
      filename: 'ui/packages/test/__test__/some-component.test.ts',
    },
    // Vitest browser import but incorrect file pattern
    {
      code: `
        import {it, expect} from '@github-ui/tests/browser'
        it('some-test', () => {})
      `,
      errors: [
        {
          messageId: 'vitestFileNames',
        },
      ],
      filename: 'ui/packages/test/__test__/invalid-component.test.ts',
    },
    // Vitest import with typo in pattern (test.browser instead of browser.test)
    {
      code: `
        import {it, expect} from '@github-ui/tests'
        it('some-test', () => {})
      `,
      errors: [
        {
          messageId: 'vitestFileNames',
        },
      ],
      filename: 'ui/packages/test/__test__/component.test.browser.ts',
    },
  ],
})
