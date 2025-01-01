// @ts-check

const {join, dirname} = require('path')
const {accessSync} = require('fs')

/**
 * @param node {import('estree').Expression | import('estree').Pattern | import('estree').PrivateIdentifier}
 * @returns {node is import('estree').Literal & {value: string}}
 */
function isStringLiteral(node) {
  return node.type === 'Literal' && typeof node.value === 'string'
}

/**
 * @param key {import('estree').Property["key"]}
 * @param value {import('estree').Property["value"]}
 * @returns {value is import('estree').ObjectExpression}
 */
function isExportsField(key, value) {
  return isStringLiteral(key) && key.value === 'exports' && value.type === 'ObjectExpression'
}

/**
 * @type {import('eslint').Rule.RuleModule}
 */
module.exports = {
  meta: {
    type: 'error',
    docs: {
      description: 'Verify that all `exports` in `package.json` point to valid file paths.',
    },
    schema: [],
  },

  create(context) {
    const directory = dirname(context.getFilename())

    return {
      Property({key, value}) {
        if (isExportsField(key, value)) {
          for (const property of value.properties) {
            if (property.type !== 'Property') {
              continue
            }
            const {value: exportPathLiteral} = property
            if (isStringLiteral(exportPathLiteral) && !exportPathLiteral.value.includes('*')) {
              try {
                accessSync(join(directory, exportPathLiteral.value))
              } catch {
                context.report({
                  node: exportPathLiteral,
                  message: `File not found: '${exportPathLiteral.value}'`,
                })
              }
            }
          }
        }
      },
    }
  },
}
