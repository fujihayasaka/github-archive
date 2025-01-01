import rule from '../accessible-default-keybindings'
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
ruleTester.run('commands-json-accessible-default-keybindings', rule as any, {
  valid: [
    validTestCase('does not report chords with 4 or fewer keys', {keybinding: 'Mod+Alt+B'}),
    validTestCase('does not report chords with 4 or fewer keys in global scope', {
      keybinding: 'Mod+Alt+B',
    }),
    validTestCase('does not report permitted override of Mod+c', {
      keybinding: 'Mod+c',
      commandName: 'Copy',
      commandDescription: 'Copy line of code',
    }),
    validTestCase('does not report permitted override of Mod+a', {
      keybinding: 'Mod+a',
      commandName: 'Select all',
      commandDescription: 'Select all lines of code',
    }),
  ],
  invalid: [
    invalidTestCase('reports chords with over 4 keys', {
      keybinding: 'Control+Shift+Meta+B+G',
      errors: ['accessibleDefaultKeybindings'],
      fixOutput: null,
    }),
    invalidTestCase('reports keybindings with only Alt as the modifier', {
      keybinding: 'Alt+b',
      errors: ['altSingleModifierError'],
      fixOutput: null,
    }),
    invalidTestCase('reports keybindings which try to override standard keyboard navigation', {
      keybinding: 'Tab',
      errors: ['keyboardNavError'],
      fixOutput: null,
    }),
    invalidTestCase('reports keybindings which interfere with screen reader commands or modifiers', {
      keybinding: 'Shift+Insert',
      errors: ['screenReaderError'],
      fixOutput: null,
    }),
    invalidTestCase('reports high-priority mod+c override that is not in the set of permitted behaviors', {
      keybinding: 'Mod+c',
      commandName: 'Go to line',
      commandDescription: 'Go to line of code',
      errors: ['defaultOverride'],
      fixOutput: null,
    }),
    invalidTestCase('reports high-priority mod+c override in a global commands.json', {
      keybinding: 'Mod+c',
      commandName: 'Copy element',
      commandDescription: 'Copy the element for usage by developer',
      errors: ['defaultOverride'],
      fixOutput: null,
      filenameOverride: 'ui/packages/ui-commands/commands.json',
    }),
    invalidTestCase('reports high priority mod+a override that is not in the set of permitted behaviors', {
      keybinding: 'Mod+a',
      commandName: 'Choose all',
      commandDescription: 'Highlights everything in the UI',
      errors: ['defaultOverride'],
      fixOutput: null,
    }),
    invalidTestCase('reports 3-key chord high-priority OS keybinding overrides', {
      keybinding: 'Mod+Shift+H',
      errors: ['defaultOverride'],
      fixOutput: null,
    }),
    invalidTestCase('reports single function keys', {
      keybinding: 'F5',
      errors: ['functionKeyError'],
      fixOutput: null,
    }),
  ],
})
