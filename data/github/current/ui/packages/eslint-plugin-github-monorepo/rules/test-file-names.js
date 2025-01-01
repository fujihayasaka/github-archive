// @ts-check
const TEST_FUNCTIONS = new Set(['describe', 'it', 'test'])
const SUFFIX_REGEX = /^.+\.test\.tsx?$/
const EXCLUDED_IMPORTS = ['@github-ui/tests']

/**
 * @type {import('eslint').Rule.RuleModule}
 */
const rule = {
  meta: {
    type: 'problem',
    docs: {
      description: 'Jest test files should have a .test.ts or .test.tsx suffix.',
    },
    messages: {
      testFileNames: 'Jest test files should have a .test.ts or .test.tsx suffix.',
    },
  },

  create(context) {
    let hasExcludedImport = false

    return {
      ImportDeclaration(node) {
        const importPath = node.source.value
        if (typeof importPath === 'string' && EXCLUDED_IMPORTS.includes(importPath)) {
          hasExcludedImport = true
        }
      },

      CallExpression(node) {
        if (hasExcludedImport) return

        const {callee} = node
        if (callee.type === 'Identifier' && TEST_FUNCTIONS.has(callee.name)) {
          const fileName = context.getFilename()
          if (fileName.match(SUFFIX_REGEX)) return
          context.report({
            node,
            messageId: 'testFileNames',
          })
        }
      },
    }
  },
}

module.exports = rule
