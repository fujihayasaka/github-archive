// @ts-check
const {ESLintUtils} = require('@typescript-eslint/utils')

module.exports = ESLintUtils.RuleCreator.withoutDocs({
  meta: {
    type: 'suggestion',
    docs: {
      description: 'Update useRef calls to be compatible with react 19 typings.',
    },
    messages: {
      useRefMessage:
        'Replace useRef() with useRef(undefined) and update the types as necessary. React 19 updates these types to force an argument be provided, in order to support that ahead of time, please use that signature. See: https://react.dev/blog/2024/04/25/react-19-upgrade-guide#useref-requires-argument',
    },
    fixable: 'code',
    schema: [], // No options
  },
  defaultOptions: [],
  create(context) {
    /** @type {string | null} */
    let reactUseRefName = null

    return {
      ImportDeclaration(node) {
        if (node.source.value === 'react') {
          const useRefSpecifier = node.specifiers.find(
            specifier =>
              specifier.type === 'ImportSpecifier' &&
              specifier.imported.type === 'Identifier' &&
              specifier.imported.name === 'useRef',
          )

          if (useRefSpecifier) {
            reactUseRefName = useRefSpecifier.local.name // Track the local name of useRef
          }
        }
      },
      CallExpression(node) {
        if (reactUseRefName && node.callee.type === 'Identifier' && node.callee.name === reactUseRefName) {
          if (node.arguments.length === 0) {
            context.report({
              node,
              messageId: 'useRefMessage',
            })
          }
        }
      },
    }
  },
})
