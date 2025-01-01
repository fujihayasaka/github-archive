// @ts-check
/**
 * @type {import('eslint').Rule.RuleModule}
 */
module.exports = {
  meta: {
    type: 'problem',
    docs: {
      description: "Force importing 'zod' only from 'zod/v4'",
    },
    messages: {
      importZodV4: "Import from 'zod/v4' instead of 'zod'.",
    },
    fixable: 'code',
    schema: [],
  },
  create(context) {
    return {
      ImportDeclaration(node) {
        if (node.source.value === 'zod') {
          context.report({
            node,
            messageId: 'importZodV4',
            fix(fixer) {
              return fixer.replaceText(node.source, "'zod/v4'")
            },
          })
        }
      },
    }
  },
}
