import rule from '../valid-key-names'
import {invalidTestCase, validTestCase} from './test-utils'
import {RuleTester} from '@typescript-eslint/rule-tester'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('valid-key-names', rule as any, {
  valid: [
    validTestCase('does not report valid keybindings', {keybinding: 'Shift+A'}),
    validTestCase('does not report dead keys when Shift is a modifier', {
      keybinding: 'Alt+Shift+N',
    }),
  ],
  invalid: [
    invalidTestCase('reports keybindings using Option with hint for Alt', {
      keybinding: 'Option+p',
      errors: ['altError'],
      fixOutput: 'Alt+p',
    }),
    invalidTestCase('reports keybindings using Command with hint for Meta', {
      keybinding: 'Cmd+p',
      errors: ['metaError'],
      fixOutput: 'Meta+p',
    }),
    invalidTestCase('reports keybindings using Esc with hint for Escape', {
      keybinding: 'Esc',
      errors: ['escapeError'],
      fixOutput: 'Escape',
    }),
    invalidTestCase('reports unknown key names', {
      keybinding: 'xyz',
      errors: ['unknownError'],
      fixOutput: null,
    }),
    invalidTestCase('reports incorrectly cased key names', {
      keybinding: 'pageup',
      errors: ['caseSensitiveError'],
      fixOutput: 'PageUp',
    }),
    invalidTestCase('reports unknown character keys', {
      keybinding: 'ß',
      errors: ['qwertyError'],
      fixOutput: null,
    }),
    invalidTestCase('reports incorrectly lowercased key names when Shift is a modifier', {
      keybinding: 'Shift+a',
      errors: ['upperCaseShiftError'],
      fixOutput: 'Shift+A',
    }),
    invalidTestCase('reports incorrectly uppercased key names when Shift is a modifier along with Mod', {
      keybinding: 'Mod+Shift+a',
      errors: ['upperCaseShiftError'],
      fixOutput: 'Mod+Shift+A',
    }),
    invalidTestCase('reports incorrectly uppercased key names when Shift is not a modifier', {
      keybinding: 'A',
      errors: ['lowerCaseShiftError'],
      fixOutput: 'a',
    }),
    invalidTestCase('reports dead keys', {
      keybinding: 'Alt+n',
      errors: ['deadKeysError'],
      fixOutput: null,
    }),
    invalidTestCase('reports dead keys with additional modifiers', {
      keybinding: 'Mod+Alt+n',
      errors: ['deadKeysError'],
      fixOutput: null,
    }),
  ],
})
