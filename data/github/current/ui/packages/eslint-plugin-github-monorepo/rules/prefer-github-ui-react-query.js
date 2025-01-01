module.exports = {
  meta: {
    type: 'suggestion',
    docs: {
      description: 'Disallow importing from @tanstack/react-query and suggest @github-ui/react-query instead',
      category: 'Best Practices',
      recommended: false,
    },
    fixable: 'code',
    schema: [], // No options required
    messages: {
      restrictedImport: "Do not import from '@tanstack/react-query'. Use '@github-ui/react-query' instead.",
    },
  },
  create(context) {
    return {
      ImportDeclaration(node) {
        if (node.source.value === '@tanstack/react-query') {
          context.report({
            node,
            messageId: 'restrictedImport',
          })
        }
      },
    }
  },
}
