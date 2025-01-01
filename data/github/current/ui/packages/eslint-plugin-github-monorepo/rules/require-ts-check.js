// @ts-check

const validExtensions = new Set(['.js', '.jsx', '.cjs', '.mjs'])
const path = require('path')

/**
 * @type {import('eslint').Rule.RuleModule}
 */
module.exports = {
  meta: {
    type: 'suggestion',
    docs: {
      description: 'Require `// @ts-check` at the top of JS files',
      recommended: false,
    },
    fixable: 'code',
    schema: [],
    messages: {
      missingTsCheck: 'File should start with `// @ts-check` comment.',
    },
  },

  create(context) {
    const filename = context.filename

    if (!validExtensions.has(path.extname(filename))) {
      return {}
    }

    return {
      Program(node) {
        const sourceCode = context.sourceCode
        const comments = sourceCode.getAllComments()

        const hasTsCheck = comments.some(
          comment => comment.type === 'Line' && comment.loc?.start.line === 1 && comment.value.trim() === '@ts-check',
        )

        if (!hasTsCheck) {
          context.report({
            node,
            loc: {line: 1, column: 0},
            messageId: 'missingTsCheck',
            fix(fixer) {
              return fixer.insertTextBeforeRange([0, 0], `// @ts-check\n`)
            },
          })
        }
      },
    }
  },
}
