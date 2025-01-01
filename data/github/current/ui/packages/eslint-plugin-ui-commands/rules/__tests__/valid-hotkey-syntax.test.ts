import rule from '../valid-hotkey-syntax'
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
ruleTester.run('valid-hotkey-syntax', rule as any, {
  valid: [validTestCase('does not report valid chords', {keybinding: 'Mod+Shift+p'})],
  invalid: [
    invalidTestCase('reports keybindings with empty chords', {
      keybinding: 'a  b',
      errors: ['emptyChordError'],
      fixOutput: 'a b',
    }),
    invalidTestCase('reports chords with empty keys', {
      keybinding: 'Mod++b',
      errors: ['emptyKeysError'],
      fixOutput: 'Mod+b',
    }),
    invalidTestCase('reports chords with duplicate keys', {
      keybinding: 'Mod+Mod+b',
      errors: ['duplicateKeyError'],
      fixOutput: 'Mod+b',
    }),
    invalidTestCase('reports chords with modifiers in wrong order', {
      keybinding: 'Shift+Mod+P',
      errors: ['sortedChordError'],
      fixOutput: 'Mod+Shift+P',
    }),
    invalidTestCase('reports keybindings with no target keys', {
      keybinding: 'Mod',
      errors: ['oneNonModiferError'],
      fixOutput: null,
    }),
    invalidTestCase('reports keybindings with multiple target keys', {
      keybinding: 'Mod+a+b',
      errors: ['oneNonModiferError'],
      fixOutput: null,
    }),
    invalidTestCase('reports both order and multiple-target errors at once', {
      keybinding: 'Shift+Mod+P+B',
      errors: ['sortedChordError', 'oneNonModiferError'],
      fixOutput: 'Mod+Shift+P+B',
    }),
  ],
})
