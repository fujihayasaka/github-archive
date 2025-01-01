import {RuleTester} from '@typescript-eslint/rule-tester'
import rule from '../no-direct-test-helper-imports'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('no-direct-test-helper-imports', rule as any, {
  valid: [
    {
      code: `
        import {fixture, html} from '@github-ui/tests'
      `,
      filename: 'ui/packages/test/some-test-file.test.ts',
    },
    {
      code: `
        import {describe, it} from '@github-ui/tests'
      `,
      filename: 'ui/packages/test/some-test-file.test.ts',
    },
  ],

  invalid: [
    {
      code: `
        import {fixture, html} from '@open-wc/testing'
      `,
      filename: 'ui/packages/test/some-test-file.test.ts',
      errors: [
        {
          messageId: 'noDirectTestHelperImport',
        },
      ],
      output: `
        import {fixture, html} from '@github-ui/tests'
      `,
    },
    {
      code: `
        import {describe, it} from '@github-ui/tests';
        import {fixture, html} from '@open-wc/testing';`,
      filename: 'ui/packages/test/some-test-file.test.ts',
      errors: [
        {
          messageId: 'noDirectTestHelperImport',
        },
      ],
      output: `
        import {describe, fixture, html, it} from '@github-ui/tests'
        `,
    },
    {
      code: `
        import {render, html} from 'lit-html'`,
      filename: 'ui/packages/test/some-test-file.test.ts',
      errors: [
        {
          messageId: 'noDirectTestHelperImport',
        },
      ],
      output: `
        import {fixture, html} from '@github-ui/tests'`,
    },
    {
      code: `
        import {afterEach, beforeEach, describe, it} from '@github-ui/tests';
        import {render, html} from 'lit-html';`,
      filename: 'ui/packages/test/some-test-file.test.ts',
      errors: [
        {
          messageId: 'noDirectTestHelperImport',
        },
      ],
      output: `
        import {afterEach, beforeEach, describe, fixture, html, it} from '@github-ui/tests'
        `,
    },
  ],
})
