import {RuleTester} from '@typescript-eslint/rule-tester'
import rule from '../prefer-browser-imports'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('prefer-browser-imports', rule as any, {
  valid: [
    {
      code: `
        import {assert, fixture, html} from '@github-ui/tests/browser'
      `,
      filename: 'ui/packages/test/some-test-file.test.ts',
    },
    {
      code: `
        import {describe, it} from '@github-ui/tests'
      `,
      filename: 'ui/packages/test/some-test-file.test.ts',
    },
    {
      code: `
        import {describe, it} from '@github-ui/tests';
        import {fixture, html} from '@github-ui/tests/browser';
      `,
      filename: 'ui/packages/test/some-test-file.test.ts',
    },
  ],

  invalid: [
    {
      code: `import {assert, fixture, html} from '@github-ui/tests'`,
      filename: 'ui/packages/test/some-test-file.test.ts',
      errors: [
        {
          messageId: 'preferBrowserSpecificImports',
          data: {specifiers: 'assert, fixture, html'},
        },
      ],
      output: `
import {assert, fixture, html} from '@github-ui/tests/browser'`,
    },
    {
      code: `
        import {describe, it, fixture, html} from '@github-ui/tests'
      `,
      filename: 'ui/packages/test/some-test-file.test.ts',
      errors: [
        {
          messageId: 'preferBrowserSpecificImports',
          data: {specifiers: 'fixture, html'},
        },
      ],
      output: `
        import {describe, it} from '@github-ui/tests'
import {fixture, html} from '@github-ui/tests/browser'
      `,
    },
    {
      code: `
        import {describe, it} from '@github-ui/tests'
import {fixture, html, aTimeout} from '@github-ui/tests'
      `,
      filename: 'ui/packages/test/some-test-file.test.ts',
      errors: [
        {
          messageId: 'preferBrowserSpecificImports',
          data: {specifiers: 'fixture, html, aTimeout'},
        },
      ],
      output: `
        import {describe, it} from '@github-ui/tests'

import {fixture, html, aTimeout} from '@github-ui/tests/browser'
      `,
    },
    {
      code: `
        import {describe, it, fixture, html, assert} from '@github-ui/tests'
      `,
      filename: 'ui/packages/test/some-test-file.test.ts',
      errors: [
        {
          messageId: 'preferBrowserSpecificImports',
          data: {specifiers: 'fixture, html, assert'},
        },
      ],
      output: `
        import {describe, it} from '@github-ui/tests'
import {fixture, html, assert} from '@github-ui/tests/browser'
      `,
    },
  ],
})
