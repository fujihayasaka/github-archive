import rule from '../no-wildcard-routes' // Adjust path as needed
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
ruleTester.run('no-wildcard-routes', rule as any, {
  valid: [
    {
      name: '✅ Route is not a wildcard',
      code: `
reactSandboxFutureAppBuilder.createQueryRouteConfig('myRoute', { path: '/' });
reactSandboxFutureAppBuilder.createQueryRouteConfig('homeRoute', { path: '/home' });
reactSandboxFutureAppBuilder.createQueryRouteConfig('validRoute', { path: '/valid' });
`,
    },
    {
      name: '✅ Route is not a wildcard using variable',
      code: `
const path = '/path';
reactSandboxFutureAppBuilder.createQueryRouteConfig('validRoute', { path });
`,
    },
    {
      name: '✅ Route contains a wildcard as subpath',
      code: `
reactSandboxFutureAppBuilder.createQueryRouteConfig('myRoute', { path: '/:owner/:repo/*' });
`,
    },
  ],

  invalid: [
    {
      name: '❌ Using wildcard route',
      code: `reactSandboxFutureAppBuilder.createQueryRouteConfig('homeRoute', { path: '*' });`,
      errors: [
        {
          messageId: 'noWildcardRoutes',
        },
      ],
    },
    {
      name: '❌ Using wildcard route with /',
      code: `reactSandboxFutureAppBuilder.createQueryRouteConfig('homeRoute', { path: '/*' });`,
      errors: [
        {
          messageId: 'noWildcardRoutes',
        },
      ],
    },
    {
      name: '❌ Using wildcard route with variable',
      code: `
const path = '*';
reactSandboxFutureAppBuilder.createQueryRouteConfig('homeRoute', { path });
`,
      errors: [
        {
          messageId: 'noWildcardRoutes',
        },
      ],
    },
  ],
})
