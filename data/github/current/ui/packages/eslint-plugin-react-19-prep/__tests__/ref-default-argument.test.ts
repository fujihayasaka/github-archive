import {RuleTester} from '@typescript-eslint/rule-tester'
import rule from '../rules/ref-default-argument'

// This is to use jsdom test environment for jest: https://github.com/jsdom/jsdom/issues/3363
if (typeof global.structuredClone === 'undefined') {
  global.structuredClone = obj => JSON.parse(JSON.stringify(obj))
}

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('react-19-prep', rule as any, {
  // tests that use the check ordered fields rule to valid package.json exports
  valid: [
    {
      code: `
const useRef = () => {}

useRef()`,
      filename: 'ui/packages/file/file.ts',
    },
    {
      code: `
import {useRef} from 'react'
const useRef = () => {}

useRef<HTMLInputElement | undefined>(undefined)
      `,
    },
  ],
  invalid: [
    {
      code: `
import {useRef} from 'react'

useRef<HTMLInputElement>()
      `,
      errors: [{messageId: 'useRefMessage'}],
    },
    {
      code: `
import {useRef} from 'react'

useRef()
      `,
      errors: [{messageId: 'useRefMessage'}],
    },
    {
      code: `
import {useRef} from 'react'

useRef<HTMLElement>()
      `,
      errors: [{messageId: 'useRefMessage'}],
    },
  ],
})
