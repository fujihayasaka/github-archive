/**
 * @type {import('eslint').Rule.RuleModule}
 */
const rule = {
  meta: {
    type: 'problem',
    docs: {
      description: 'Ensure queryConfigs.concreteRequest uses an imported identifier ending in _QUERY',
      recommended: 'error',
    },
    messages: {
      invalidQueryConfig: 'concreteRequest must be a directly-imported identifier ending in `_QUERY`, got `{{name}}`.',
    },
    schema: [],
  },
  create(context) {
    const imported = new Set()

    return {
      ImportDeclaration(node) {
        for (const specifier of node.specifiers) {
          if (
            (specifier.type === 'ImportSpecifier' || specifier.type === 'ImportDefaultSpecifier') &&
            specifier.local.name.endsWith('_QUERY')
          ) {
            imported.add(specifier.local.name)
          }
        }
      },

      CallExpression(node) {
        const callee = node.callee
        if (callee.type === 'Identifier' && callee.name === 'registerNavigatorApp' && node.arguments.length === 2) {
          const fn = node.arguments[1]
          if (fn.type === 'ArrowFunctionExpression' || fn.type === 'FunctionExpression') {
            let obj = null
            if (fn.body.type === 'BlockStatement') {
              for (const stmt of fn.body.body) {
                if (stmt.type === 'ReturnStatement' && stmt.argument && stmt.argument.type === 'ObjectExpression') {
                  obj = stmt.argument
                  break
                }
              }
            } else if (fn.body.type === 'ObjectExpression') {
              obj = fn.body
            }
            if (!obj) return

            // find routes: [ ... ]
            const routesProp = obj.properties.find(
              p =>
                p.type === 'Property' &&
                p.key.type === 'Identifier' &&
                p.key.name === 'routes' &&
                p.value.type === 'ArrayExpression',
            )
            if (!routesProp) return

            for (const el of routesProp.value.elements) {
              if (!el || el.type !== 'CallExpression') continue

              const args = el.arguments
              if (args[0].type !== 'ObjectExpression') continue

              const qcProp = args[0].properties.find(
                p =>
                  p.type === 'Property' &&
                  p.key.type === 'Identifier' &&
                  p.key.name === 'queryConfigs' &&
                  p.value.type === 'ObjectExpression',
              )
              if (!qcProp) continue

              for (const entry of qcProp.value.properties) {
                if (entry.type !== 'Property' || entry.value.type !== 'ObjectExpression') {
                  continue
                }

                const concreteProp = entry.value.properties.find(
                  p => p.type === 'Property' && p.key.type === 'Identifier' && p.key.name === 'concreteRequest',
                )
                if (!concreteProp) continue

                const val = concreteProp.value
                const name = val.type === 'Identifier' ? val.name : context.getSourceCode().getText(val)

                if (val.type !== 'Identifier' || !name.endsWith('_QUERY') || !imported.has(name)) {
                  context.report({
                    node: val,
                    messageId: 'invalidQueryConfig',
                    data: {name},
                  })
                }
              }
            }
          }
        }
      },
    }
  },
}

module.exports = rule
