import {RuleTester} from '@typescript-eslint/rule-tester'

import noWaitForSelectorVisible from '../rules/no-wait-for-selector-visible'

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
ruleTester.run('no-wait-for-selector-visible', noWaitForSelectorVisible as any, {
  valid: [
    {code: `await expect(page.locator(_('settings-side-nav'))).toBeVisible()`},
    {code: `await expect(this.page.locator(_('settings-side-nav'))).toBeVisible()`},
    {code: `const sideNav = await page.locator(_('settings-side-nav'))\nawait expect(sideNav).toBeVisible()`},
    // Unrelated, but caused a crash once
    {code: `const field = await (testId ? page.$(_(testId)) : page.$(selector))`},
  ],
  invalid: [
    {
      code: `await page.waitForSelector(_('settings-side-nav'), { state: 'visible' })`,
      errors: [{messageId: 'noWaitForSelectorVisible'}],
      output: `await expect(page.locator(_('settings-side-nav'))).toBeVisible()`,
    },
    {
      code: `await this.page.waitForSelector(_('settings-side-nav'), { state: 'visible' })`,
      errors: [{messageId: 'noWaitForSelectorVisible'}],
      output: `await expect(this.page.locator(_('settings-side-nav'))).toBeVisible()`,
    },
    {
      code: `const sideNav = await page.waitForSelector(_('settings-side-nav'), { state: 'visible' })`,
      errors: [{messageId: 'noWaitForSelectorVisible'}],
      output: `const sideNav = page.locator(_('settings-side-nav'))\nawait expect(sideNav).toBeVisible()`,
    },
  ],
})
