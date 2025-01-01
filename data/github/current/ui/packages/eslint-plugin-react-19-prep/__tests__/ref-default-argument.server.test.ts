import {RuleTester} from '@github-ui/tests/eslint'
import rule from '../rules/ref-default-argument'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

ruleTester.run('react-19-prep', rule, {
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
