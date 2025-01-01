/**
 * @type {import('eslint').Rule.RuleModule}
 */
const rule = {
  meta: {
    type: 'problem',
    docs: {
      description: 'Ensure test utilities are replaced with UI-specific utilities (e.g., jest -> vi)',
      category: 'Best Practices',
      recommended: false,
    },
    messages: {
      replaceTestUtility: 'Replace "{{original}}" with "{{replacement}}" from "@github-ui/tests".',
    },
    fixable: 'code',
    schema: [],
  },
  create(context) {
    const utilityReplacements = {
      test: 'it',
      jest: 'vi',
    }

    function isTestFile(filename) {
      return /\.(browser|server)\.test\.tsx?$/.test(filename)
    }

    return {
      CallExpression(node) {
        const filename = context.getFilename()

        if (!isTestFile(filename)) {
          return
        }

        let originalUtility = null
        let replacementUtility = null

        if (node.callee.type === 'Identifier' && utilityReplacements[node.callee.name]) {
          originalUtility = node.callee.name
          replacementUtility = utilityReplacements[originalUtility]
        } else if (
          node.callee.type === 'MemberExpression' &&
          node.callee.object.type === 'Identifier' &&
          utilityReplacements[node.callee.object.name]
        ) {
          originalUtility = node.callee.object.name
          replacementUtility = utilityReplacements[originalUtility]
        }

        if (originalUtility && replacementUtility) {
          context.report({
            node: node.callee.type === 'Identifier' ? node.callee : node.callee.object,
            messageId: 'replaceTestUtility',
            data: {
              original: originalUtility,
              replacement: replacementUtility,
            },
            fix(fixer) {
              return fixer.replaceText(
                node.callee.type === 'Identifier' ? node.callee : node.callee.object,
                replacementUtility,
              )
            },
          })
        }
      },
    }
  },
}

module.exports = rule
