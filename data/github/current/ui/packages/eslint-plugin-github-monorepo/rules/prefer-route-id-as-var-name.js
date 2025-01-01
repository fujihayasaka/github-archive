// @ts-check
const CAMEL_CASE_REGEX = /^[a-z][a-zA-Z0-9]*$/
const VALID_IDENTIFIER_REGEX = /^[a-zA-Z$_][a-zA-Z0-9$_]*$/

/**
 * @type {import('eslint').Rule.RuleModule}
 */
const rule = {
  meta: {
    type: 'problem',
    docs: {
      description: 'Data routes must be named the same as their id.',
    },
    fixable: 'code',
    hasSuggestions: true,
    messages: {
      invalidCamelCase: `The first argument ("{{varName}}") must be in camelCase.`,
      invalidIdentifier: `The first argument ("{{varName}}") is not a valid JavaScript identifier.`,
      invalidVariableNameForAssignment: `The variable name ("{{assignedVar}}") must match the first argument ("{{routeId}}") of createQueryRouteConfig.`,
    },
  },
  create(context) {
    return {
      CallExpression(node) {
        if (
          node.callee.type === 'MemberExpression' &&
          'name' in node.callee.property &&
          node.callee.property.name === 'createQueryRouteConfig'
        ) {
          const firstArg =
            node.arguments[0] && node.arguments[0].type === 'Literal' && typeof node.arguments[0].value === 'string'
              ? node.arguments[0].value
              : null

          if (firstArg) {
            const isCamelCase = CAMEL_CASE_REGEX.test(firstArg)
            const isValidIdentifier = VALID_IDENTIFIER_REGEX.test(firstArg)

            if (!isCamelCase) {
              context.report({
                node,
                messageId: 'invalidCamelCase',
                data: {
                  varName: firstArg,
                },
              })
            }

            if (!isValidIdentifier) {
              context.report({
                node,
                messageId: 'invalidIdentifier',
                data: {
                  varName: firstArg,
                },
              })
            }
          }
        }
      },
      VariableDeclarator(node) {
        if (
          node.init &&
          node.init.type === 'CallExpression' &&
          node.init.callee.type === 'MemberExpression' &&
          'name' in node.init.callee.property &&
          node.init.callee.property.name === 'createQueryRouteConfig'
        ) {
          if (!('name' in node.id)) return
          const assignedVar = node.id.name
          const firstArg =
            node.init.arguments[0] &&
            node.init.arguments[0].type === 'Literal' &&
            typeof node.init.arguments[0].value === 'string'
              ? node.init.arguments[0].value
              : null

          if (firstArg) {
            const isValidIdentifier = VALID_IDENTIFIER_REGEX.test(firstArg)

            if (!isValidIdentifier) {
              context.report({
                node,
                messageId: 'invalidIdentifier',
                data: {
                  varName: firstArg,
                },
              })
              return
            }

            if (assignedVar !== firstArg) {
              context.report({
                node,
                messageId: 'invalidVariableNameForAssignment',
                data: {
                  assignedVar,
                  routeId: firstArg,
                },
                fix(fixer) {
                  return fixer.replaceText(node.id, firstArg)
                },
              })
            }
          }
        }
      },
    }
  },
}

module.exports = rule
