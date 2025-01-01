// @ts-check

const {ESLintUtils} = require('@typescript-eslint/utils')
/** @typedef {import('@typescript-eslint/types').TSESTree.JSXAttribute} JSXAttribute */

// Identifiers to not support in code
const unsupportedIdentifiers = new Set(['registerNavigatorApp', 'jsonRoute'])

module.exports = ESLintUtils.RuleCreator.withoutDocs({
  meta: {
    docs: {
      description: 'Prefer the usage of DataRouter over jsonRoute and other unsupported identifiers or imports.',
    },
    messages: {
      unsupportedIdentifier:
        'Usage of "{{name}}" is no longer supported. Consider migrating to DataRouter instead (https://github.com/github/github/blob/master/ui/packages/react-core/future/docs/data-router)',
    },
    type: 'problem',
    schema: [],
  },
  defaultOptions: [],
  create(context) {
    return {
      CallExpression(node) {
        // Existing identifier check
        if (node.callee.type === 'Identifier' && unsupportedIdentifiers.has(node.callee.name)) {
          context.report({
            messageId: 'unsupportedIdentifier',
            data: {name: node.callee.name},
            node: node.callee,
          })
        }
      },
    }
  },
})
