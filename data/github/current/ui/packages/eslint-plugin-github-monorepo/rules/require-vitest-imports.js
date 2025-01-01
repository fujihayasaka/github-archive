/**
 * @type {import('eslint').Rule.RuleModule}
 */
const rule = {
  meta: {
    type: 'problem',
    docs: {
      description: 'Ensure Vitest suites import test utilities from @github-ui/tests',
      category: 'Best Practices',
      recommended: false,
    },
    messages: {
      requireTestImports: 'Missing test utilities import(s): {{specifiers}}. Add imports from "@github-ui/tests".',
    },
    fixable: 'code',
    schema: [],
  },
  create(context) {
    const testSpecifiers = ['describe', 'beforeEach', 'beforeAll', 'afterAll', 'afterEach', 'it', 'expect', 'vi']

    function isTestFile(filename) {
      return /\.(browser|server)\.test\.tsx?$/.test(filename)
    }

    // Find all references to test utilities in the code
    function findUsedTestUtilities(sourceCode) {
      const usedUtilities = new Set()
      const usedTypes = new Set()
      const identifiers = []

      for (const node of sourceCode.ast.body) {
        if (node.type === 'ImportDeclaration') continue

        // Collect all identifiers in the AST
        for (const key of sourceCode.visitorKeys[node.type]) {
          if (node[key]) {
            if (Array.isArray(node[key])) {
              for (const child of node[key]) {
                if (child && typeof child === 'object') {
                  collectIdentifiers(child, identifiers, sourceCode)
                }
              }
            } else if (typeof node[key] === 'object' && node[key] !== null) {
              collectIdentifiers(node[key], identifiers, sourceCode)
            }
          }
        }
      }

      // Check if each test utility is used
      for (const specifier of testSpecifiers) {
        const isUsed = identifiers.some(id => id.name === specifier)
        if (isUsed) {
          usedUtilities.add(specifier)
        }
      }

      return {usedUtilities, usedTypes}
    }

    // Helper to collect all identifiers in the AST
    function collectIdentifiers(node, identifiers, sourceCode) {
      if (!node || typeof node !== 'object') return

      if (node.type === 'Identifier') {
        identifiers.push(node)
      }

      // Recursively check all properties
      for (const key of Object.keys(node)) {
        if (key === 'parent' || key === 'range' || key === 'loc') continue // Skip non-AST properties

        if (Array.isArray(node[key])) {
          for (const child of node[key]) {
            if (child && typeof child === 'object') {
              collectIdentifiers(child, identifiers, sourceCode)
            }
          }
        } else if (typeof node[key] === 'object' && node[key] !== null) {
          collectIdentifiers(node[key], identifiers, sourceCode)
        }
      }
    }

    return {
      Program(node) {
        const filename = context.getFilename()

        // Skip if not a test file
        if (!isTestFile(filename)) {
          return
        }

        const sourceCode = context.sourceCode
        const imports = sourceCode.ast.body.filter(n => n.type === 'ImportDeclaration')

        // Find any direct imports from 'vitest'
        const vitestImport = imports.find(n => n.source.value === 'vitest')

        // Skip this rule if direct imports from 'vitest' are found
        if (vitestImport) return

        // Find all imports from '@github-ui/tests'
        const testImport = imports.find(n => n.source.value === '@github-ui/tests')

        // Find test utilities actually used in the file
        const {usedUtilities, usedTypes} = findUsedTestUtilities(sourceCode)

        // Collect imports that already exist
        const importedSpecifiers = new Set()
        const importedTypes = new Set()

        if (testImport) {
          for (const specifier of testImport.specifiers) {
            if (specifier.type === 'ImportSpecifier') {
              if (specifier.importKind === 'type') {
                importedTypes.add(specifier.imported.name)
              } else {
                importedSpecifiers.add(specifier.imported.name)
              }
            }
          }
        }

        // Check which required utilities are missing
        const missingSpecifiers = [...usedUtilities].filter(s => !importedSpecifiers.has(s))
        const missingTypeSpecifiers = [...usedTypes].filter(s => !importedTypes.has(s))

        if (missingSpecifiers.length > 0 || missingTypeSpecifiers.length > 0) {
          const allMissingSpecifiers = [
            ...missingSpecifiers,
            ...(missingTypeSpecifiers.length > 0 ? [`type ${missingTypeSpecifiers.join(', ')}`] : []),
          ]

          // Create the fix
          context.report({
            node,
            messageId: 'requireTestImports',
            data: {
              specifiers: allMissingSpecifiers.join(', '),
            },
            fix(fixer) {
              const fixes = []

              if (testImport) {
                // Update existing import
                const existingSpecifiers = testImport.specifiers
                  .filter(s => s.importKind !== 'type')
                  .map(s => s.imported.name)

                const existingTypeSpecifiers = testImport.specifiers
                  .filter(s => s.importKind === 'type')
                  .map(s => s.imported.name)

                const allSpecifiers = [...new Set([...existingSpecifiers, ...missingSpecifiers])].sort()
                let importStatement = `import {${allSpecifiers.join(', ')}`

                // Handle type imports
                if (existingTypeSpecifiers.length > 0 || missingTypeSpecifiers.length > 0) {
                  const allTypeSpecifiers = [...existingTypeSpecifiers, ...missingTypeSpecifiers].sort()

                  if (allTypeSpecifiers.length > 0) {
                    importStatement += `, type ${allTypeSpecifiers.join(', ')}`
                  }
                }

                importStatement += `} from '@github-ui/tests'`

                fixes.push(fixer.replaceText(testImport, importStatement))
              } else {
                // Create new import
                let newImport = `import {${missingSpecifiers.join(', ')}`

                if (missingTypeSpecifiers.length > 0) {
                  newImport += missingSpecifiers.length
                    ? `, type ${missingTypeSpecifiers.join(', ')}`
                    : `type ${missingTypeSpecifiers.join(', ')}`
                }

                newImport += `} from '@github-ui/tests'`

                // Find position to insert - at the top of the file after shebang/comments
                const firstNode = sourceCode.ast.body[0]
                fixes.push(fixer.insertTextBefore(firstNode, `${newImport}\n`))
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
