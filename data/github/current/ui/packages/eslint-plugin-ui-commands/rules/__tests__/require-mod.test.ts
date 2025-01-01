import rule from '../require-mod'
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
ruleTester.run('require-mod', rule as any, {
  valid: [validTestCase('Does not report keybindings using Mod', {keybinding: 'Mod+Shift+P'})],
  invalid: [
    invalidTestCase('reports keybindings using Control', {
      keybinding: 'Control+Shift+P',
      errors: ['useMod'],
      fixOutput: 'Mod+Shift+P',
    }),
    invalidTestCase('reports keybindings using Meta', {
      keybinding: 'Meta+Shift+P',
      errors: ['useMod'],
      fixOutput: 'Mod+Shift+P',
    }),
    invalidTestCase('double-reports keybindings using both', {
      keybinding: 'Control+Meta+P',
      errors: ['useMod', 'useMod'],
      fixOutput: ['Mod+Meta+P', 'Mod+Mod+P'],
    }),
  ],
})
