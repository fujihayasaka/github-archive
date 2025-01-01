/**
 * @type {import('eslint').Rule.RuleModule}
 */
const rule = {
  meta: {
    type: 'problem',
    docs: {
      description: 'Ensure browser-specific imports are moved to "@github-ui/tests/browser"',
      category: 'Best Practices',
      recommended: false,
    },
    messages: {
      preferBrowserSpecificImports:
        'Prefer browser-specific imports ({{specifiers}}) from "@github-ui/tests" to "@github-ui/tests/browser".',
    },
    fixable: 'code',
    schema: [],
  },
  create(context) {
    const browserSpecifiers = [
      'assert',
      'fixture',
      'fixtureCleanup',
      'html',
      'waitUntil',
      'aTimeout',
      'nextFrame',
      'elementUpdated',
      'chai',
      'spread',
    ]

    function reportAndFix(node) {
      const sourceCode = context.sourceCode
      const importSpecifiers = node.specifiers.map(specifier => specifier.local.name)
      const browserImports = importSpecifiers.filter(specifier => browserSpecifiers.includes(specifier))
      const nonBrowserImports = importSpecifiers.filter(specifier => !browserSpecifiers.includes(specifier))

      if (browserImports.length > 0) {
        context.report({
          node,
          data: {
            specifiers: browserImports.join(', '),
          },
          messageId: 'preferBrowserSpecificImports',
          fix(fixer) {
            const fixes = []
            const existingBrowserImport = sourceCode.ast.body.find(
              n => n.type === 'ImportDeclaration' && n.source.value === '@github-ui/tests/browser',
            )

            // Update the original import to exclude browser-specific imports
            if (nonBrowserImports.length > 0) {
              fixes.push(fixer.replaceText(node, `import {${nonBrowserImports.join(', ')}} from '@github-ui/tests'`))
            } else {
              fixes.push(fixer.remove(node))
            }

            // Add or update the "@github-ui/tests/browser" import
            if (existingBrowserImport) {
              const existingSpecifiers = existingBrowserImport.specifiers.map(specifier => specifier.local.name)
              const combinedSpecifiers = Array.from(new Set([...existingSpecifiers, ...browserImports])).sort()
              fixes.push(
                fixer.replaceText(
                  existingBrowserImport,
                  `import {${combinedSpecifiers.join(', ')}} from '@github-ui/tests/browser'`,
                ),
              )
            } else {
              fixes.push(
                fixer.insertTextAfter(node, `\nimport {${browserImports.join(', ')}} from '@github-ui/tests/browser'`),
              )
            }

            return fixes
          },
        })
      }
    }

    return {
      ImportDeclaration(node) {
        if (node.source.value === '@github-ui/tests') {
          reportAndFix(node)
        }
      },
    }
  },
}

module.exports = rule
