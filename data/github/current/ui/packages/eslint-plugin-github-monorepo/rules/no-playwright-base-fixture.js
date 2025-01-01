function findPlaywrightImport(context) {
  const importDeclarations = context.sourceCode.ast.body.filter(n => n.type === 'ImportDeclaration') || []
  const playwrightImport = importDeclarations.find(n => n.source.value === '@playwright/test')

  if (!playwrightImport) return

  return playwrightImport.specifiers.find(i => i.imported.name === 'test')
}

module.exports = {
  meta: {
    type: 'error',
    docs: {
      description: "Disallow creating fixtures using playwright's default.",
    },
    schema: [],
    fixable: 'code',
    messages: {
      noPlaywrightBaseFixture:
        "Do not inherit fixtures from playwright's default. Use the 'page.fixture' fixture as base instead.",
    },
  },

  create(context) {
    return {
      MemberExpression(node) {
        const {object, property} = node
        if (property?.type === 'Identifier' && property?.name === 'extend') {
          const playwrightImport = findPlaywrightImport(context)

          if (!playwrightImport) return

          const testImportName = playwrightImport.local.name

          if (testImportName !== object.name) return

          context.report({
            messageId: 'noPlaywrightBaseFixture',
            node,
          })
        }
      },
    }
  },
}
