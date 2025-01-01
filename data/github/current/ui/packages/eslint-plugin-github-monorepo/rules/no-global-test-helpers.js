/**
 * @type {import('eslint').Rule.RuleModule}
 */
const rule = {
  meta: {
    type: 'problem',
    docs: {
      description: 'Disallow global test lifecycle helpers and enforce importing from @github-ui/browser-tests',
      category: 'Best Practices',
      recommended: false,
    },
    messages: {
      avoidGlobalTestHelpers: 'Import test helpers directly: {{importStatement}}',
    },
    fixable: 'code',
    schema: [],
  },
  create(context) {
    const deprecatedTestHelpersMap = new Map([
      ['suite', 'describe'],
      ['setup', 'beforeEach'],
      ['suiteSetup', 'before'],
      ['suiteTeardown', 'after'],
      ['teardown', 'afterEach'],
      ['test', 'it'],
    ])
    const nodesToFix = []

    return {
      CallExpression(node) {
        if (node.callee.type === 'Identifier' && deprecatedTestHelpersMap.has(node.callee.name)) {
          const replacement = deprecatedTestHelpersMap.get(node.callee.name)
          nodesToFix.push({node, replacement})
        }
      },
      'Program:exit': function (node) {
        if (nodesToFix.length > 0) {
          const testHelpers = nodesToFix.map(({replacement}) => replacement).sort()
          const importStatement = `import {${testHelpers.join(', ')}} from '@github-ui/browser-tests'`
          const sourceCode = context.sourceCode
          const existingImport = sourceCode.ast.body.find(
            n => n.type === 'ImportDeclaration' && n.source.value === '@github-ui/browser-tests',
          )

          context.report({
            node,
            data: {
              importStatement,
            },
            messageId: 'avoidGlobalTestHelpers',
            fix(fixer) {
              const fixes = []

              if (existingImport) {
                const existingSpecifiers = existingImport.specifiers.map(specifier => specifier.local.name)
                const newSpecifiers = Array.from(new Set([...testHelpers, ...existingSpecifiers])).sort()
                fixes.push(
                  fixer.replaceText(
                    existingImport,
                    `import {${newSpecifiers.join(', ')}} from '@github-ui/browser-tests'`,
                  ),
                )
              } else {
                fixes.push(fixer.insertTextBefore(node.body[0], `${importStatement}\n`))
              }

              for (const {node: innerNode, replacement} of nodesToFix) {
                fixes.push(fixer.replaceText(innerNode.callee, replacement))
              }

              return fixes
            },
          })
        }
      },
    }
  },
}

module.exports = rule
