// @ts-check
import {closest} from 'fastest-levenshtein'

/**
 * @type {(getWorkspacePackages: () => Set<string>) => import('eslint').Rule.RuleModule}
 */
function createRule(getWorkspacePackages) {
  /**
   * @type {Set<string> | null}
   */
  let cachedWorkspacePackages = null

  /**
   * @returns {Set<string>}
   */
  function workspacePackages() {
    return (cachedWorkspacePackages ??= getWorkspacePackages())
  }
  /**
   * @type {import('eslint').Rule.RuleModule}
   */
  const rule = {
    meta: {
      type: 'problem',
      docs: {
        description: 'Ensure all managed dependencies are part of the npm workspace',
        category: 'Best Practices',
        recommended: true,
      },
      schema: [], // No options
    },
    create(context) {
      const packages = workspacePackages()
      return {
        ObjectExpression(node) {
          const parent = node.parent
          if (
            parent &&
            parent.type === 'VariableDeclarator' &&
            parent.id &&
            parent.id.type === 'Identifier' &&
            parent.id.name === 'managedDependencies'
          ) {
            for (const property of node.properties) {
              if (property.type === 'Property' && property.value && property.value.type === 'Literal') {
                const value = String(property.value.value) // Get the value of the property
                if (!packages.has(value)) {
                  const closestMatch = closest(value, Array.from(packages))
                  context.report({
                    node: property.value,
                    message: `'${value}' is not part of the npm workspace. Did you mean '${closestMatch}'?`,
                  })
                }
              }
            }
          }
        },
      }
    },
  }

  return rule
}
export default createRule
