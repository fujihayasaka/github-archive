import rule from '../prefer-route-id-as-var-name' // Adjust path as needed
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
ruleTester.run('prefer-route-id-as-var-name', rule as any, {
  valid: [
    {
      name: '✅ Variable name matches first argument and is camelCase',
      code: `
const myRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig('myRoute', { path: '/' });
const homeRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig('homeRoute', { path: '/home' });
const validRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig('validRoute', { path: '/valid' });
`,
    },
    {
      name: '✅ Function call without assignment, but with correct casing',
      code: `reactSandboxFutureAppBuilder.createQueryRouteConfig('anotherValidRoute', { path: '/test' });`,
    },
  ],

  invalid: [
    {
      name: '❌ Variable name does not match first argument',
      code: `const myRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig('homeRoute', { path: '/' });`,
      errors: [
        {
          messageId: 'invalidVariableNameForAssignment',
          data: {
            assignedVar: 'myRoute',
            routeId: 'homeRoute',
          },
        },
      ],
      output: `const homeRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig('homeRoute', { path: '/' });`,
    },

    {
      name: '❌ First argument is not camelCase (PascalCase)',
      code: `const myRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig('MyRoute', { path: '/' });`,
      errors: [
        {
          messageId: 'invalidVariableNameForAssignment',
          data: {
            assignedVar: 'myRoute',
            routeId: 'MyRoute',
          },
        },
        {
          messageId: 'invalidCamelCase',
          data: {
            varName: 'MyRoute',
          },
        },
      ],
      output: `const MyRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig('MyRoute', { path: '/' });`,
    },

    {
      name: '❌ First argument is not a valid JavaScript identifier (starts with a number)',
      code: `const myRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig('123route', { path: '/' });`,
      errors: [
        {
          messageId: 'invalidIdentifier',
          data: {
            varName: '123route',
          },
        },
        {
          messageId: 'invalidCamelCase',
          data: {
            varName: '123route',
          },
        },
        {
          messageId: 'invalidIdentifier',
          data: {
            varName: '123route',
          },
        },
      ],
    },

    {
      name: '❌ First argument is snake_case',
      code: `const myRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig('my_route', { path: '/' });`,
      errors: [
        {
          messageId: 'invalidVariableNameForAssignment',
          data: {
            assignedVar: 'myRoute',
            routeId: 'my_route',
          },
        },
        {
          messageId: 'invalidCamelCase',
          data: {
            varName: 'my_route',
          },
        },
      ],
      output: `const my_route = reactSandboxFutureAppBuilder.createQueryRouteConfig('my_route', { path: '/' });`,
    },

    {
      name: '❌ First argument is uppercase (constant-like)',
      code: `const myRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig('MY_ROUTE', { path: '/' });`,
      errors: [
        {
          messageId: 'invalidVariableNameForAssignment',
          data: {
            assignedVar: 'myRoute',
            routeId: 'MY_ROUTE',
          },
        },
        {
          messageId: 'invalidCamelCase',
          data: {
            varName: 'MY_ROUTE',
          },
        },
      ],
      output: `const MY_ROUTE = reactSandboxFutureAppBuilder.createQueryRouteConfig('MY_ROUTE', { path: '/' });`,
    },

    {
      name: '❌ Function call without assignment, but invalid Pascal casing',
      code: `reactSandboxFutureAppBuilder.createQueryRouteConfig('NotCamelCase', { path: '/' });`,
      errors: [
        {
          messageId: 'invalidCamelCase',
          data: {
            varName: 'NotCamelCase',
          },
        },
      ],
    },
    {
      name: '❌ Function call without assignment, but invalid Snake casing',
      code: `reactSandboxFutureAppBuilder.createQueryRouteConfig('wrong_format', { path: '/' });`,
      errors: [
        {
          data: {
            varName: 'wrong_format',
          },
          messageId: 'invalidCamelCase',
        },
      ],
    },
    {
      name: '❌ Function call without assignment, but invalid numeric start',
      code: `reactSandboxFutureAppBuilder.createQueryRouteConfig('999wrongStart', { path: '/' });`,
      errors: [
        {
          messageId: 'invalidCamelCase',
          data: {
            varName: '999wrongStart',
          },
        },
        {
          messageId: 'invalidIdentifier',
          data: {
            varName: '999wrongStart',
          },
        },
      ],
    },
  ],
})
