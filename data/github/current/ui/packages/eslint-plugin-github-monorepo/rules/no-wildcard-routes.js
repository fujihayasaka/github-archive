// @ts-check

const {ESLintUtils} = require('@typescript-eslint/utils')
/** @typedef {import('@typescript-eslint/types').TSESTree.JSXAttribute} JSXAttribute */

const WILDCARD_ROOTS = ['*', '/*']

module.exports = ESLintUtils.RuleCreator.withoutDocs({
  meta: {
    docs: {
      description: 'We are discouraging the use of wildcard routes, please use well-defined routes.',
    },
    messages: {
      noWildcardRoutes: 'Do not use wildcard routes, prefer using well-defined routes.',
    },
    schema: [],
    type: 'problem',
  },
  defaultOptions: [],
  create(context) {
    return {
      CallExpression(node) {
        if (
          node.callee.type === 'MemberExpression' &&
          'name' in node.callee.property &&
          node.callee.property.name === 'createQueryRouteConfig'
        ) {
          const secondArg = node.arguments[1]

          if (!secondArg || secondArg.type !== 'ObjectExpression') return

          const path = secondArg.properties.find(
            property =>
              property.type === 'Property' && property.key.type === 'Identifier' && property.key.name === 'path',
          )

          if (!path || path.type !== 'Property') return

          const pathValue = path.value
          let route
          // literal assignment
          if (pathValue.type === 'Literal') {
            route = pathValue.value
          }
          // variable use
          if (pathValue.type === 'Identifier') {
            const scope = context.sourceCode.getScope(node)
            const variable = scope.variables.find(v => v.name === pathValue.name)

            if (
              !variable ||
              !variable.defs[0] ||
              variable.defs[0].node.type !== 'VariableDeclarator' ||
              variable.defs[0].node.init?.type !== 'Literal'
            )
              return
            route = variable.defs[0].node.init.value
          }

          if (!WILDCARD_ROOTS.includes(String(route))) return

          context.report({
            node: pathValue,
            messageId: 'noWildcardRoutes',
          })
        }
      },
    }
  },
})
