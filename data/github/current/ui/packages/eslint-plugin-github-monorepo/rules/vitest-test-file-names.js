// @ts-check
/**
 * ESLint rule to enforce Vitest test files have the proper naming pattern:
 * *.browser.test.*, *.server.test.*, or *.jsdom.test.*
 */

const VITEST_IMPORTS = ['@github-ui/tests', '@github-ui/tests/browser']
const FILE_PATTERN_REGEX = /^.+\.(browser|server|jsdom)\.test\.(tsx|ts|js)$/

/**
 * @type {import('eslint').Rule.RuleModule}
 */
const rule = {
  meta: {
    type: 'problem',
    docs: {
      description: 'Vitest test files should have a *.(browser|server|jsdom).test.* pattern.',
    },
    messages: {
      vitestFileNames: 'Vitest test files should follow the pattern: *.{browser|server|jsdom}.test.{tsx|ts|js}',
    },
  },

  create(context) {
    // Flag to check if file has any Vitest imports
    let hasVitestImport = false

    return {
      // Check import statements
      ImportDeclaration(node) {
        const importPath = node.source.value
        if (typeof importPath === 'string' && VITEST_IMPORTS.includes(importPath)) {
          hasVitestImport = true
        }
      },

      // At the end of the program, check if the file has Vitest imports and verify its name
      'Program:exit': function (node) {
        if (hasVitestImport) {
          const fileName = context.getFilename()
          if (!fileName.match(FILE_PATTERN_REGEX)) {
            context.report({
              node,
              messageId: 'vitestFileNames',
            })
          }
        }
      },
    }
  },
}

module.exports = rule
