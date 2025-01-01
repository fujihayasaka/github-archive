import {RuleTester} from '@typescript-eslint/rule-tester'

import noLocatorTestId from '../rules/no-locator-test-id'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// This is to use jsdom test environment for jest: https://github.com/jsdom/jsdom/issues/3363
if (typeof global.structuredClone === 'undefined') {
  global.structuredClone = obj => JSON.parse(JSON.stringify(obj))
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('no-locator-test-id', noLocatorTestId as any, {
  valid: [
    {code: `getByTestId('side-panel')`},
    {code: `getByTestId("side-panel")`},
    {code: 'getByTestId(`side-panel`)'},
    {code: 'getByTestId(`side-${"panel"}`)'},
    {code: `page.getByTestId('side-panel')`},
    {code: `this.page.getByTestId('side-panel')`},
    {code: 'page.getByTestId(`side-${"panel"}`)'},
    {code: 'this.page.getByTestId(`side-${"panel"}`)'},
    {code: 'something.getByTestId("side-panel")'},
  ],
  invalid: [
    {
      code: `page.locator(_('side-panel'))`,
      errors: [{messageId: 'useGetByTestId'}],
      output: `page.getByTestId('side-panel')`,
    },
    {
      code: `something.locator(_('side-panel'))`,
      errors: [{messageId: 'useGetByTestId'}],
      output: `something.getByTestId('side-panel')`,
    },
    {
      code: `await expect(page.locator(_('general-settings'))).toBeVisible()`,
      errors: [{messageId: 'useGetByTestId'}],
      output: `await expect(page.getByTestId('general-settings')).toBeVisible()`,
    },
    {
      code: `await expect(this.page.locator(_('general-settings'))).toBeVisible()`,
      errors: [{messageId: 'useGetByTestId'}],
      output: `await expect(this.page.getByTestId('general-settings')).toBeVisible()`,
    },
  ],
})
