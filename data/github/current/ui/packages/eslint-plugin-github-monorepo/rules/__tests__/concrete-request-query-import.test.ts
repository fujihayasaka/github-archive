import {RuleTester} from 'eslint'
import rule from '../concrete-request-query-import'

const ruleTester = new RuleTester()

ruleTester.run('concrete-request-query-import', rule, {
  valid: [
    // correct import + suffix + usage
    {
      code: `
                import SOME_QUERY from './queries'
                registerNavigatorApp('app', () => ({
                  routes: [
                    route({
                      queryConfigs: {
                        pageQuery: { concreteRequest: SOME_QUERY }
                      }
                    })
                  ]
                }))
            `,
    },
    // named import form, function expression, no block
    {
      code: `
                import { ANOTHER_QUERY } from './other'
                registerNavigatorApp('app', function() {
                  return {
                    routes: [
                      route({
                        queryConfigs: {
                          pageQuery: { concreteRequest: ANOTHER_QUERY }
                        }
                      })
                    ]
                  }
                })
            `,
    },
  ],
  invalid: [
    // missing import entirely
    {
      code: `
                registerNavigatorApp('app', () => ({
                  routes: [
                    route({
                      queryConfigs: {
                        pageQuery: { concreteRequest: MISSING_QUERY }
                      }
                    })
                  ]
                }))
            `,
      errors: [
        {
          messageId: 'invalidQueryConfig',
          data: {name: 'MISSING_QUERY'},
          type: 'Identifier',
        },
      ],
    },
    // imported but wrong suffix
    {
      code: `
                import A_GOOD_QUERY from './query'
                import IT_IS_A_QUERY_I_PROMISE from './notquery'
                registerNavigatorApp('app', () => ({
                  routes: [
                    route({
                      queryConfigs: {
                        pageQuery: { concreteRequest: A_GOOD_QUERY }
                      }
                    }),
                    route({
                      queryConfigs: {
                        pageQuery: { concreteRequest: IT_IS_A_QUERY_I_PROMISE }
                      }
                    })
                  ]
                }))
            `,
      errors: [
        {
          messageId: 'invalidQueryConfig',
          data: {name: 'IT_IS_A_QUERY_I_PROMISE'},
          type: 'Identifier',
        },
      ],
    },
    // proxied import
    {
      code: `
                import A_QUERY from './foo'
                const PROXIED_QUERY = A_QUERY
                registerNavigatorApp('app', () => ({
                  routes: [
                    route({
                      queryConfigs: {
                        pageQuery: { concreteRequest: PROXIED_QUERY }
                      }
                    })
                  ]
                }))
            `,
      errors: [
        {
          messageId: 'invalidQueryConfig',
          data: {name: 'PROXIED_QUERY'},
          type: 'Identifier',
        },
      ],
    },
    // inline object instead of identifier
    {
      code: `
                import A_QUERY from './foo'
                registerNavigatorApp('app', () => ({
                  routes: [
                    route({
                      queryConfigs: {
                        pageQuery: { concreteRequest: { inline: 'object' } }
                      }
                    })
                  ]
                }))
            `,
      errors: [
        {
          messageId: 'invalidQueryConfig',
          data: {name: "{ inline: 'object' }"},
          type: 'ObjectExpression',
        },
      ],
    },
  ],
})
