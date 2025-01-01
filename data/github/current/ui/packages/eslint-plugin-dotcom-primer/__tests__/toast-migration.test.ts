import {RuleTester} from '@typescript-eslint/rule-tester'

import rule from '../rules/toast-migration'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('toast-migration', rule as any, {
  valid: [{code: `notAToast()`}],
  invalid: [
    {
      code: `something.addToast()`,
      errors: [{messageId: 'toastMigration'}],
    },
    {
      code: `something.addPersistedToast()`,
      errors: [{messageId: 'toastMigration'}],
    },
    {
      code: `addToast()`,
      errors: [{messageId: 'toastMigration'}],
    },
    {
      code: `addPersistedToast()`,
      errors: [{messageId: 'toastMigration'}],
    },
  ],
})
