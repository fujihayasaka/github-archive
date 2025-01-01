import {RuleTester} from 'eslint'
import rule from '../filename-convention'

const testCode = "var foo = 'bar';"
const ruleTester = new RuleTester()

ruleTester.run('filename-convention', rule, {
  valid: [
    // *.js patterns
    {
      code: testCode,
      filename: 'foo-bar.js',
    },
    {
      code: testCode,
      filename: 'foo-bar-v1.js',
    },
    {
      code: testCode,
      filename: 'foo64-bar-baz.js',
    },
    {
      code: testCode,
      filename: 'foo-bar.test.js',
    },
    // *.ts patterns
    {
      code: testCode,
      filename: 'foo-bar.ts',
    },
    {
      code: testCode,
      filename: 'foo-bar-v1.ts',
    },
    {
      code: testCode,
      filename: 'foo64-bar-baz.ts',
    },
    {
      code: testCode,
      filename: 'foo-bar.test.ts',
    },
    // *.tsx patterns
    {
      code: testCode,
      filename: 'FooBar.tsx',
    },
    {
      code: testCode,
      filename: 'FooBBar.tsx',
    },
    {
      code: testCode,
      filename: 'FooBarV1.tsx',
    },
    {
      code: testCode,
      filename: 'FooBar.test.tsx',
    },
    // /hooks patterns
    {
      code: testCode,
      filename: 'use-foo-bar.js',
    },
    {
      code: testCode,
      filename: 'use-foo-bar.ts',
    },
    {
      code: testCode,
      filename: 'useFooBar.tsx',
    },
    // test patterns
    {
      code: testCode,
      filename: '**/__tests__/foo-bar.test.ts',
    },
    {
      code: testCode,
      filename: '**/test-utils/foo-bar.ts',
    },
    {
      code: testCode,
      filename: 'eslint.config.mjs',
    },
    // validate that the rule does not run on other file types
    {
      code: testCode,
      filename: 'fooBar$.json',
    },
  ],

  invalid: [
    // *.js patterns
    {
      code: testCode,
      filename: 'fooBar.js',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
    {
      code: testCode,
      filename: 'foo_bar.js',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
    {
      code: testCode,
      filename: 'FooBar.js',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
    {
      code: testCode,
      filename: 'fooBar1.js',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
    {
      code: testCode,
      filename: 'fooBar$.js',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
    // *.ts patterns
    {
      code: testCode,
      filename: 'fooBar.ts',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
    {
      code: testCode,
      filename: 'foo_bar.ts',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
    {
      code: testCode,
      filename: 'FooBar.ts',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
    {
      code: testCode,
      filename: 'fooBar1.ts',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
    {
      code: testCode,
      filename: 'fooBar$.ts',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
    // *.tsx patterns
    {
      code: testCode,
      filename: 'foo-bar.tsx',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
    {
      code: testCode,
      filename: 'fooBar.tsx',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
    {
      code: testCode,
      filename: 'Foo-bar.tsx',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
    {
      code: testCode,
      filename: 'Foo_bar.tsx',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
    {
      code: testCode,
      filename: 'FooBar$.tsx',
      errors: [{messageId: 'failsConvention', column: 1, line: 1}],
    },
  ],
})
