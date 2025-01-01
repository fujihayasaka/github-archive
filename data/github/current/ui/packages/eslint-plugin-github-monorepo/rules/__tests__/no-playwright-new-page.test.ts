import {RuleTester} from '@typescript-eslint/rule-tester'
import rule from '../no-playwright-new-page'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

ruleTester.run('no-playwright-new-page', rule as never, {
  valid: [
    {
      code: `
import {createPage} from 'spec/lib/createPage'
import test from '../fixtures/api.fixture'

test('some test', async ({browser}) => {
  const page = await createPage(browser)
})
      `,
      filename: 'test/e2e/spec/someTest.spec.ts',
    },
    {
      code: `
import {createPage} from 'spec/lib/createPage'
import test from '../fixtures/api.fixture'

test('some test', async ({context}) => {
  const page = await createPage(context)
})
      `,
      filename: 'test/e2e/spec/someTest.spec.ts',
    },
  ],

  invalid: [
    {
      code: `
import test from '../fixtures/api.fixture'

test('some test', async ({browser}) => {
  const page = await browser.newPage()
})
      `,
      filename: 'test/e2e/spec/someTest.spec.ts',
      errors: [
        {
          messageId: 'noPlaywrightNewPage',
        },
      ],
      output: `
import test from '../fixtures/api.fixture'
import {createPage} from 'spec/lib/createPage'

test('some test', async ({browser}) => {
  const page = await createPage(browser)
})
      `,
    },
    {
      code: `
import test from '../fixtures/api.fixture'

test('some test', async ({context}) => {
  const page = await context.newPage()
})
      `,
      filename: 'test/e2e/spec/someTest.spec.ts',
      errors: [
        {
          messageId: 'noPlaywrightNewPage',
        },
      ],
      output: `
import test from '../fixtures/api.fixture'
import {createPage} from 'spec/lib/createPage'

test('some test', async ({context}) => {
  const page = await createPage(context)
})
      `,
    },
    {
      code: `
test('some test', async ({context}) => {
  const page = await context.newPage()
})
      `,
      filename: 'test/e2e/spec/someTest.spec.ts',
      errors: [
        {
          messageId: 'noPlaywrightNewPage',
        },
      ],
      output: `import {createPage} from 'spec/lib/createPage'
test('some test', async ({context}) => {
  const page = await createPage(context)
})
      `,
    },
    {
      code: `
import {createPage} from 'spec/lib/createPage'

test('some test', async ({context}) => {
  const page = await context.newPage()
})
      `,
      filename: 'test/e2e/spec/someTest.spec.ts',
      errors: [
        {
          messageId: 'noPlaywrightNewPage',
        },
      ],
      output: `
import {createPage} from 'spec/lib/createPage'

test('some test', async ({context}) => {
  const page = await createPage(context)
})
      `,
    },
  ],
})
