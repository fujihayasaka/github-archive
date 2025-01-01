/**
 * Check if the file path is a JS(X) or TS(X) file in `app/assets/modules/react-shared` or `ui/packages`.
 * @param {import('eslint').Rule.RuleContext} context
 */
const isReactUi = context =>
  /(app\/assets\/modules\/react-shared\/|ui\/packages\/).*\.[tj]sx?$/.test(context.getFilename())

// This is to use jsdom test environment for jest: https://github.com/jsdom/jsdom/issues/3363
if (typeof global.structuredClone === 'undefined') {
  global.structuredClone = obj => JSON.parse(JSON.stringify(obj))
}

/** @type {import("eslint").Rule.RuleModule} */
module.exports = {
  meta: {
    type: 'problem',
    docs: {
      description: 'Prefer using `ui-commands` over manual shortcut logic.',
    },
    messages: {
      useUiCommands: 'Prefer using the {{isReactUi}} instead of manual shortcut logic',
    },
    schema: [],
  },

  create(context) {
    return {
      MemberExpression(node) {
        const {object, property} = node

        if (
          object.type === 'Identifier' &&
          object.name.startsWith('e') &&
          property.type === 'Identifier' &&
          // TODO: Add check for event.code & event.shiftKey
          /^((meta|ctrl|alt)Key|key)$/.test(property.name)
        ) {
          context.report({
            node,
            // ui-commands is only available for React code for now
            data: {
              isReactUi: isReactUi(context) ? '`@github-ui/ui-commands` platform' : 'data-hotkey',
            },
            messageId: 'useUiCommands',
          })
        }
      },
    }
  },
}
