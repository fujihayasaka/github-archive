// @ts-check
const {ESLintUtils, AST_NODE_TYPES} = require('@typescript-eslint/utils')

const INVALID_RETURN_MESSAGE_ID = 'invalidReturn'
module.exports.INVALID_RETURN_MESSAGE_ID = INVALID_RETURN_MESSAGE_ID

module.exports = ESLintUtils.RuleCreator.withoutDocs({
  meta: {
    type: 'problem',
    docs: {
      description: 'Prevent returning non-function values from ref callbacks',
    },
    messages: {
      [INVALID_RETURN_MESSAGE_ID]:
        'In React 19 Ref callbacks should return void or a cleanup function, not a value. To prepare for this, please ensure that your ref callbacks do not return any value in React 18',
    },
    schema: [],
  },
  defaultOptions: [],
  create(context) {
    return {
      JSXAttribute(node) {
        if (node.name.name !== 'ref' || !node.value || node.value.type !== AST_NODE_TYPES.JSXExpressionContainer) {
          return
        }

        const {expression} = node.value

        if (
          expression.type !== AST_NODE_TYPES.ArrowFunctionExpression &&
          expression.type !== AST_NODE_TYPES.FunctionExpression
        ) {
          return
        }

        const {body} = expression

        if (body.type === AST_NODE_TYPES.BlockStatement) {
          for (const stmt of body.body) {
            if (
              stmt.type === AST_NODE_TYPES.ReturnStatement &&
              stmt.argument &&
              stmt.argument.type !== AST_NODE_TYPES.FunctionExpression &&
              stmt.argument.type !== AST_NODE_TYPES.ArrowFunctionExpression
            ) {
              context.report({node: stmt.argument, messageId: INVALID_RETURN_MESSAGE_ID})
            }
          }
        } else if (
          body.type !== AST_NODE_TYPES.FunctionExpression &&
          body.type !== AST_NODE_TYPES.ArrowFunctionExpression
        ) {
          context.report({node: body, messageId: INVALID_RETURN_MESSAGE_ID})
        }
      },
    }
  },
})
