module.exports = {
  meta: {
    type: 'suggestion',
    docs: {
      description: 'Disallow importing `QueryClientProvider` from `@tanstack/react-query` or `@github-ui/react-query`',
      category: 'Best Practices',
      recommended: false,
    },
    schema: [], // No options required
    messages: {
      restrictedImport:
        'Do not use `QueryClientProvider` as we are moving to a shared Query Client model and there is one mounted for you. More information at https://gh.io/react-query',
    },
  },
  create(context) {
    return {
      ImportDeclaration(node) {
        if (node.source.value !== '@github-ui/react-query' && node.source.value !== '@tanstack/react-query') {
          return
        }

        for (const specifier of node.specifiers) {
          if (specifier.type !== 'ImportSpecifier') {
            continue
          }
          if (specifier.imported.name === 'QueryClientProvider') {
            context.report({
              node: specifier,
              messageId: 'restrictedImport',
              data: {name: specifier.imported.name},
            })
          }
        }
      },
    }
  },
}
