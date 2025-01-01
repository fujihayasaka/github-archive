/**
 * @type {import('eslint').Rule.RuleModule}
 */
const rule = {
  meta: {
    type: 'problem',
    docs: {
      description: 'Ensure browser-based tests only import test helpers and hooks from @github-ui/tests',
      category: 'Best Practices',
      recommended: false,
    },
    messages: {
      noDirectTestHelperImport:
        'Avoid importing from {{importSource}}. Use imports from "@github-ui/tests" for test helpers instead.',
    },
    fixable: 'code',
    schema: [],
  },
  create(context) {
    function reportAndFix(node, importSource) {
      context.report({
        node,
        data: {
          importSource,
        },
        messageId: 'noDirectTestHelperImport',
        fix(fixer) {
          const sourceCode = context.sourceCode
          const importDeclarations = sourceCode.ast.body.filter(
            n => n.type === 'ImportDeclaration' && n.source.value === importSource,
          )
          const existingImport = sourceCode.ast.body.find(
            n => n.type === 'ImportDeclaration' && n.source.value === '@github-ui/tests',
          )
          const fixes = []

          for (const importDeclaration of importDeclarations) {
            const specifiers = importDeclaration.specifiers.map(specifier => specifier.local.name)
            const newSpecifiers = specifiers.map(specifier => (specifier === 'render' ? 'fixture' : specifier)).sort()

            if (existingImport) {
              const existingSpecifiers = existingImport.specifiers.map(specifier => specifier.local.name)
              const combinedSpecifiers = Array.from(new Set([...existingSpecifiers, ...newSpecifiers])).sort()
              fixes.push(
                fixer.replaceText(existingImport, `import {${combinedSpecifiers.join(', ')}} from '@github-ui/tests'`),
              )
              fixes.push(fixer.remove(importDeclaration))
            } else {
              fixes.push(
                fixer.replaceText(importDeclaration, `import {${newSpecifiers.join(', ')}} from '@github-ui/tests'`),
              )
            }
          }

          return fixes
        },
      })
    }

    return {
      ImportDeclaration(node) {
        const importSource = node.source.value

        if (importSource === '@open-wc/testing') {
          reportAndFix(node, '@open-wc/testing')
        }

        if (importSource === 'lit-html') {
          reportAndFix(node, 'lit-html')
        }
      },
    }
  },
}

module.exports = rule
