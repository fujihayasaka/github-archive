// @ts-check
const {AST_NODE_TYPES} = require('@typescript-eslint/utils')

/**
 * @type {import('@typescript-eslint/utils').TSESLint.RuleModule<'discourageConstEnum' | 'discourageEnum'>}
 */
module.exports = {
  meta: {
    type: 'suggestion',
    docs: {
      description:
        'Convert TypeScript enums (including const enums) into const objects with a shadowed type, preserving export declarations and handling missing member values',
      category: 'Best Practices',
      recommended: false,
    },
    fixable: 'code',
    schema: [], // No options
    messages: {
      discourageConstEnum: "Const enum '{{enumName}}' can be replaced with a const object and a shadowed type.",
      discourageEnum: "Enum '{{enumName}}' can be replaced with a const object and a shadowed type.",
    },
  },
  create(context) {
    return {
      TSEnumDeclaration(node) {
        // Check if the enum is exported
        const isExported =
          node.parent.type === AST_NODE_TYPES.ExportNamedDeclaration ||
          node.parent.type === AST_NODE_TYPES.ExportDefaultDeclaration

        const enumName = node.id.name

        // Create entries for the const object
        const objectEntries = node.body.members.map(member => {
          /** @type {string} */
          let key
          if (member.id.type === AST_NODE_TYPES.Identifier) {
            key = member.id.name // Normal enum key
          } else if (member.id.type === AST_NODE_TYPES.Literal) {
            key = String(member.id.value) // String literal enum key
          } else {
            key = '' // Unexpected case (should never happen in normal enums)
          }
          const value = member.initializer
            ? context.sourceCode.getText(member.initializer) // Use the initializer if it exists
            : `"${key}"` // Default to using the key as the string value
          return `${key}: ${value}`
        })

        // Generate the transformed text
        const exportPrefix = isExported ? 'export ' : ''
        const objectText = `const ${enumName} = {\n  ${objectEntries.join(',\n  ')}\n} as const;`
        const typeText = `${exportPrefix}type ${enumName} = (typeof ${enumName})[keyof typeof ${enumName}];`

        // Report and autofix
        context.report({
          node,
          messageId: node.const ? 'discourageConstEnum' : 'discourageEnum',
          data: {
            enumName,
          },
          fix(fixer) {
            return fixer.replaceText(node, `${objectText}\n\n${typeText}`)
          },
        })
      },
    }
  },
}
