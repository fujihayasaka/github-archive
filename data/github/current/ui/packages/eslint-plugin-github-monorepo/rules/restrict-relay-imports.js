// @ts-check

const {ESLintUtils} = require('@typescript-eslint/utils')
/** @typedef {import('@typescript-eslint/types').TSESTree.JSXAttribute} JSXAttribute */

// Modules to not support in imports
const unsupportedModules = new Set(['@github-ui/relay-route', 'react-relay'])

module.exports = ESLintUtils.RuleCreator.withoutDocs({
  meta: {
    docs: {
      description: 'Prefer the usage of DataRouter over RelayRoute and other unsupported identifiers or imports.',
    },
    messages: {
      unsupportedImport:
        'Importing "{{module}}" is no longer supported. Consider migrating to DataRouter instead (https://github.com/github/github/blob/master/ui/packages/react-core/future/docs/data-router)',
    },
    type: 'problem',
    schema: [],
  },
  defaultOptions: [],
  create(context) {
    return {
      ImportDeclaration(node) {
        if (unsupportedModules.has(node.source.value)) {
          context.report({
            messageId: 'unsupportedImport',
            data: {module: node.source.value},
            node: node.source,
          })
        }
      },
      // Also catch require() calls
      CallExpression(node) {
        if (
          node.callee.type === 'Identifier' &&
          node.callee.name === 'require' &&
          node.arguments[0] &&
          node.arguments[0].type === 'Literal' &&
          unsupportedModules.has(node.arguments[0].value?.toString() || '')
        ) {
          context.report({
            messageId: 'unsupportedImport',
            data: {module: node.arguments[0].value},
            node: node.arguments[0],
          })
        }
      },
    }
  },
})
