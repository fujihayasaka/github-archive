module.exports = {
  meta: {
    type: 'error',
    docs: {
      description: 'Disallow the use of browser/context.newPage since it skips the CDN configuration.',
    },
    schema: [],
    fixable: 'code',
    messages: {
      noPlaywrightNewPage: 'Do not create a new page manually, use the `createPage` helper instead.',
    },
  },

  create(context) {
    return {
      CallExpression(node) {
        const {callee} = node
        if (callee.property?.type === 'Identifier' && callee.property?.name === 'newPage') {
          context.report({
            messageId: 'noPlaywrightNewPage',
            node,
            fix(fixer) {
              const importDeclarations = context.sourceCode.ast.body.filter(n => n.type === 'ImportDeclaration') || []
              const existingImport = importDeclarations.find(n => n.source.value === 'spec/lib/createPage')
              const callerName = callee.object.name
              const replaceCall = fixer.replaceText(node, `createPage(${callerName})`)

              if (existingImport) {
                return replaceCall
              }

              if (importDeclarations.length > 0) {
                return [
                  replaceCall,
                  fixer.insertTextAfter(
                    importDeclarations[importDeclarations.length - 1],
                    "\nimport {createPage} from 'spec/lib/createPage'",
                  ),
                ]
              }

              return [replaceCall, fixer.insertTextAfterRange([0, 0], "import {createPage} from 'spec/lib/createPage'")]
            },
          })
        }
      },
    }
  },
}
