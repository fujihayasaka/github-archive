import rule from '../valid-ids'
import {RuleTester} from '@typescript-eslint/rule-tester'
import {filename} from './test-utils'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

function commandIdJson(commandId: string) {
  return JSON.stringify({
    serviceName: 'Test',
    serviceId: 'test',
    commands: {
      [commandId]: {
        name: 'Test command',
        description: 'Test command',
      },
    },
  })
}

function serviceIdJson(serviceId: string) {
  return JSON.stringify({
    serviceName: 'Test',
    serviceId,
    commands: {
      'test-id': {
        name: 'Test command',
        description: 'Test command',
      },
    },
  })
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('valid-ids', rule as any, {
  valid: [
    {name: 'Does not report valid service ID', code: serviceIdJson('test-service'), filename},
    {name: 'Does not report valid command ID', code: commandIdJson('test-command'), filename},
  ],
  invalid: [
    {
      name: 'Reports empty service ID',
      code: serviceIdJson(''),
      errors: [{messageId: 'emptyError'}],
      output: null,
      filename,
    },
    {
      name: 'Reports empty command ID',
      code: commandIdJson(''),
      errors: [{messageId: 'emptyError'}],
      output: null,
      filename,
    },
    {
      name: 'Reports invalid service ID',
      code: serviceIdJson('not alphanumeric!'),
      errors: [{messageId: 'invalidError'}],
      output: null,
      filename,
    },
    {
      name: 'Reports invalid command ID',
      code: commandIdJson('#notAlphanumeric'),
      errors: [{messageId: 'invalidError'}],
      output: null,
      filename,
    },
    {
      name: 'Autofixes PascalCase ID',
      code: commandIdJson('TestId'),
      errors: [{messageId: 'invalidError'}],
      output: commandIdJson('test-id'),
      filename,
    },
    {
      name: 'Autofixes camelCase ID',
      code: commandIdJson('testId'),
      errors: [{messageId: 'invalidError'}],
      output: commandIdJson('test-id'),
      filename,
    },
    {
      name: 'Autofixes snake_case ID',
      code: commandIdJson('test_id'),
      errors: [{messageId: 'invalidError'}],
      output: commandIdJson('test-id'),
      filename,
    },
  ],
})
