const message =
  'Toasts degrade the overall user experience and are therefore considered a discouraged pattern. Please consider using alternatives as described in: https://primer.style/ui-patterns/notification-messaging. If you have any questions, reach out in #primer.'

// This is to use jsdom test environment for jest: https://github.com/jsdom/jsdom/issues/3363
if (typeof global.structuredClone === 'undefined') {
  global.structuredClone = obj => JSON.parse(JSON.stringify(obj))
}

// @ts-check
/**
 * This rule prevents the addToast and addPersistedToast functions from being used.
 * Toasts have accessibility and usability issue.
 */

/**
 * @typedef {import('eslint').Rule.RuleModule} RuleModule
 * @typedef {import('eslint').Rule.Node} Node
 */

/** @type {RuleModule} */
module.exports = {
  meta: {
    type: 'problem',
    docs: {
      description: message,
      url: 'https://github.com/github/primer/discussions/3080',
    },
    messages: {
      toastMigration: message,
    },
    schema: [],
  },

  create(context) {
    return {
      CallExpression(node) {
        const {callee} = node
        if (callee.type === 'Identifier' && (callee.name === 'addToast' || callee.name === 'addPersistedToast')) {
          context.report({
            node,
            messageId: 'toastMigration',
          })
        } else if (
          callee.type === 'MemberExpression' &&
          'name' in callee.property &&
          (callee.property.name === 'addToast' || callee.property.name === 'addPersistedToast')
        ) {
          context.report({
            node,
            messageId: 'toastMigration',
          })
        }
      },
    }
  },
}
