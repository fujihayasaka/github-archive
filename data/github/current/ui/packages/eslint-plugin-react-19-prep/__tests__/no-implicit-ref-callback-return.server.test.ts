import {RuleTester} from '@github-ui/tests/eslint'
import rule, {INVALID_RETURN_MESSAGE_ID} from '../rules/no-implicit-ref-callback-return'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2020,
      ecmaFeatures: {
        jsx: true,
      },
      sourceType: 'module',
    },
  },
})

ruleTester.run('no-implicit-ref-callback-return', rule, {
  valid: [
    {
      code: `<input ref={node => { if (node) console.log(node); }} />`,
    },
    {
      code: `<input ref={node => { return; }} />`,
    },
    {
      code: `<input ref={node => () => cleanup(node)} />`,
    },
    {
      code: `<input ref={function(node) { /* no return */ }} />`,
    },
    {
      code: `<input ref={function(node) { return () => cleanup(node); }} />`,
    },
  ],

  invalid: [
    {
      code: `<input ref={node => node && console.log(node)} />`,
      errors: [{messageId: INVALID_RETURN_MESSAGE_ID}],
    },
    {
      code: `<input ref={node => 'not a function'} />`,
      errors: [{messageId: INVALID_RETURN_MESSAGE_ID}],
    },
    {
      code: `<input ref={node => 123} />`,
      errors: [{messageId: INVALID_RETURN_MESSAGE_ID}],
    },
    {
      code: `<input ref={node => <div />} />`,
      errors: [{messageId: INVALID_RETURN_MESSAGE_ID}],
    },
    {
      code: `<input ref={function(node) { return 42; }} />`,
      errors: [{messageId: INVALID_RETURN_MESSAGE_ID}],
    },
    {
      code: `<input ref={function(node) { return 'hello'; }} />`,
      errors: [{messageId: INVALID_RETURN_MESSAGE_ID}],
    },
  ],
})
