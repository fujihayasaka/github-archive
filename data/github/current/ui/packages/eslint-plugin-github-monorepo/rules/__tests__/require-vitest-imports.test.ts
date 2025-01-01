import {RuleTester} from '@typescript-eslint/rule-tester'
import rule from '../require-vitest-imports'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('require-vitest-imports', rule as any, {
  valid: [
    {
      code: `
        import {describe, it, expect} from '@github-ui/tests'

        describe('test suite', () => {
          it('works', () => {
            expect(true).toBe(true)
          })
        })
      `,
      filename: 'ui/packages/test/example.browser.test.ts',
    },
    {
      // Should not enforce on non-matching filenames
      code: `
        describe('test suite', () => {
          it('works', () => {
            expect(true).toBe(true)
          })
        })
      `,
      filename: 'ui/packages/test/example.test.ts',
    },
    {
      // Should pass if used imports are already present (even with extras)
      code: `
        import {describe, beforeEach, beforeAll, afterAll, afterEach, it, expect, vi, type Mock, someOtherFunction} from '@github-ui/tests'

        describe('test suite', () => {
          it('works', () => {
            expect(true).toBe(true)
          })
        })
      `,
      filename: 'ui/packages/test/example.server.test.ts',
    },
    {
      // No imports required if no test utilities are used
      code: `
        // Just some regular code, no test utilities used
        const sum = (a, b) => a + b;
        console.log(sum(1, 2));
      `,
      filename: 'ui/packages/test/example.browser.test.ts',
    },
  ],

  invalid: [
    {
      // Missing imports that are used in the code
      code: `
        // No imports
        describe('test suite', () => {
          it('works', () => {
            expect(true).toBe(true)
          })
        })
      `,
      filename: 'ui/packages/test/example.browser.test.ts',
      errors: [
        {
          messageId: 'requireTestImports',
          data: {specifiers: 'describe, it, expect'},
        },
      ],
      output: `
        // No imports
        import {describe, it, expect} from '@github-ui/tests'
describe('test suite', () => {
          it('works', () => {
            expect(true).toBe(true)
          })
        })
      `,
    },
    {
      // Partially importing from @github-ui/tests
      code: `
        import {describe} from '@github-ui/tests'

        describe('test suite', () => {
          it('works', () => {
            expect(true).toBe(true)
          })
        })
      `,
      filename: 'ui/packages/test/example.server.test.ts',
      errors: [
        {
          messageId: 'requireTestImports',
          data: {specifiers: 'it, expect'},
        },
      ],
      output: `
        import {describe, expect, it} from '@github-ui/tests'

        describe('test suite', () => {
          it('works', () => {
            expect(true).toBe(true)
          })
        })
      `,
    },
    {
      // Has some imports and also other unrelated imports
      code: `
        import React from 'react'
        import {describe} from '@github-ui/tests'
        import {render} from '@testing-library/react'

        describe('test suite', () => {
          beforeEach(() => {
            console.log('setup')
          })

          it('works', () => {
            expect(true).toBe(true)
          })

          afterEach(() => {
            console.log('cleanup')
          })
        })
      `,
      filename: 'ui/packages/test/example.browser.test.tsx',
      errors: [
        {
          messageId: 'requireTestImports',
          data: {specifiers: 'beforeEach, afterEach, it, expect'},
        },
      ],
      output: `
        import React from 'react'
        import {afterEach, beforeEach, describe, expect, it} from '@github-ui/tests'
        import {render} from '@testing-library/react'

        describe('test suite', () => {
          beforeEach(() => {
            console.log('setup')
          })

          it('works', () => {
            expect(true).toBe(true)
          })

          afterEach(() => {
            console.log('cleanup')
          })
        })
      `,
    },
    {
      // Only used beforeAll and afterAll
      code: `
        const setupTests = () => {
          beforeAll(() => {
            console.log('global setup')
          })

          afterAll(() => {
            console.log('global cleanup')
          })
        }

        setupTests()
      `,
      filename: 'ui/packages/test/example.server.test.ts',
      errors: [
        {
          messageId: 'requireTestImports',
          data: {specifiers: 'beforeAll, afterAll'},
        },
      ],
      output: `
        import {beforeAll, afterAll} from '@github-ui/tests'
const setupTests = () => {
          beforeAll(() => {
            console.log('global setup')
          })

          afterAll(() => {
            console.log('global cleanup')
          })
        }

        setupTests()
      `,
    },
    {
      // Verify that existing imports are kept intact
      code: `
        import {describe, it} from '@github-ui/tests'
        import someOtherThing from 'other-lib'

        describe('test suite', () => {
          beforeEach(() => {
            // Setup
          })

          it('works', () => {
            expect(true).toBe(true)
          })
        })
      `,
      filename: 'ui/packages/test/example.browser.test.ts',
      errors: [
        {
          messageId: 'requireTestImports',
          data: {specifiers: 'beforeEach, expect'},
        },
      ],
      output: `
        import {beforeEach, describe, expect, it} from '@github-ui/tests'
        import someOtherThing from 'other-lib'

        describe('test suite', () => {
          beforeEach(() => {
            // Setup
          })

          it('works', () => {
            expect(true).toBe(true)
          })
        })
      `,
    },
  ],
})
