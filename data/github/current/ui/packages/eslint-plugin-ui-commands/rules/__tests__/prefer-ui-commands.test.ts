import rule from '../no-manual-shortcut-logic'
import {RuleTester} from '@typescript-eslint/rule-tester'

const filename = 'ui/packages/test-package/some-logic.ts'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('prefer-ui-commands', rule as any, {
  valid: [
    {
      name: 'Accessing allowed properties',
      code: 'event.target;',
      filename,
    },
    {
      name: 'Accessing `key` on non-event',
      code: 'blob.key;',
      filename,
    },
  ],
  invalid: [
    {
      name: '`event.key` in ui-packages code',
      code: 'event.key;',
      filename,
      errors: [{messageId: 'useUiCommands'}],
      output: null,
    },
    {
      name: '`event.key` in react-shared code',
      code: 'event.key;',
      filename: 'app/assets/modules/react-shared/logic.ts',
      errors: [{messageId: 'useUiCommands'}],
      output: null,
    },
    {
      name: '`event.key` in non-React UI code',
      code: 'event.key;',
      filename: 'index.js',
      errors: [{messageId: 'useUiCommands'}],
      output: null,
    },
    {
      name: '`event.ctrlKey`',
      code: 'event.ctrlKey;',
      filename,
      errors: [{messageId: 'useUiCommands'}],
      output: null,
    },
    {
      name: 'Accessing `key` on event named `e`',
      code: 'e.key;',
      filename,
      errors: [{messageId: 'useUiCommands'}],
      output: null,
    },
  ],
})
