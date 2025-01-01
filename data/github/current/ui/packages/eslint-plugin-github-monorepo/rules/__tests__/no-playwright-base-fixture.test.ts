import {RuleTester} from '@typescript-eslint/rule-tester'
import rule from '../no-playwright-base-fixture'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

ruleTester.run('no-playwright-base-fixture', rule as never, {
  valid: [
    {
      code: `
import {test} from '@playwright/test'
import base from './setup.fixture'

const fixture = base.extend<object>()

export default fixture
      `,
      filename: 'test/e2e/spec/fixtures/someFixture.fixture.ts',
    },
  ],

  invalid: [
    {
      code: `
import {test as base} from '@playwright/test'

const fixture = base.extend<object>()

export default fixture
      `,
      filename: 'test/e2e/spec/fixtures/someFixture.fixture.ts',
      errors: [
        {
          messageId: 'noPlaywrightBaseFixture',
        },
      ],
    },
    {
      code: `
import {test} from '@playwright/test'

const fixture = test.extend<object>()

export default fixture
      `,
      filename: 'test/e2e/spec/fixtures/someFixture.fixture.ts',
      errors: [
        {
          messageId: 'noPlaywrightBaseFixture',
        },
      ],
    },
  ],
})
