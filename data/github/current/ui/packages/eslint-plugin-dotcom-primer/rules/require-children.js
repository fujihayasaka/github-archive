// @ts-check

const {isImportedFrom} = require('eslint-plugin-primer-react/src/utils/is-imported-from.js')

// This is to use jsdom test environment for jest: https://github.com/jsdom/jsdom/issues/3363
if (typeof global.structuredClone === 'undefined') {
  global.structuredClone = obj => JSON.parse(JSON.stringify(obj))
}

/**
 * @typedef {import('eslint').Rule.RuleContext} RuleContext
 * @typedef {import('eslint').Rule.RuleModule} RuleModule
 * @typedef {import('eslint').Rule.Node} Node
 * @typedef {import('eslint').Scope.Scope} Scope
 * @typedef {import('@typescript-eslint/types').TSESTree.JSXElement} JSXElement
 * @typedef {import('@typescript-eslint/types').TSESTree.JSXFragment} JSXFragment
 * @typedef {import('@typescript-eslint/types').TSESTree.JSXChild} JSXChild
 */

/** @param node {JSXChild} */
function getComponentName(node) {
  if (node.type === 'JSXElement' && node.openingElement.name.type === 'JSXIdentifier') {
    return node.openingElement.name.name
  }
  if (
    node.type === 'JSXElement' &&
    node.openingElement.name.type === 'JSXMemberExpression' &&
    node.openingElement.name.object.type === 'JSXIdentifier'
  ) {
    return `${node.openingElement.name.object.name}.${node.openingElement.name.property.name}`
  }
  return null
}

/**
 * @param node {JSXElement | JSXFragment | {children: JSXChild[]}}
 * @param name {string}
 * @param depth {number}
 */
function hasChild(node, name, depth = 0) {
  // Limit recursion
  if (depth > 3) return false
  for (const child of node.children) {
    // Handle <Node><><Name /></></Node>
    if (child.type === 'JSXFragment') {
      return hasChild(child, name, depth + 1)
    }
    // Handle <Node>{true && <Name />}</Node>
    if (
      child.type === 'JSXExpressionContainer' &&
      child.expression.type === 'LogicalExpression' &&
      child.expression.left.type === 'Literal' &&
      child.expression.left.value === true &&
      child.expression.right.type === 'JSXElement'
    ) {
      return hasChild({children: [child.expression.right]}, name, depth + 1)
    }
    // Handle <Node>{child}</Node>
    if (child.type === 'JSXExpressionContainer' && child.expression.type === 'Identifier') {
      // FIXME: Figure out how to handle this
      return false
    }
    // Handle <Node>{...children}</Node>
    if (child.type === 'JSXSpreadChild') {
      // FIXME: Figure out how to handle this
      return false
    }
    // Handle <Node><Name /></Node>
    if (getComponentName(child) === name) {
      return true
    }
  }
  return false
}

/** @type {RuleModule} */
module.exports = {
  meta: {
    type: 'suggestion',
    docs: {
      description: 'Require components to have specific children',
    },
    messages: {
      requireChildren:
        '<{{parent}}> requires a <{{child}}> child, but one wasn’t provided. Check <{{parent}}>’s children.{{message}}',
    },
    schema: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          parent: {type: 'string'},
          child: {type: 'string'},
          message: {type: 'string'},
          module: {type: 'string'},
        },
        required: ['parent', 'child'],
        additionalProperties: false,
      },
      uniqueItems: true,
      minItems: 1,
    },
  },

  /** @param context {RuleContext & {sourceCode: { getScope(node: JSXElement["openingElement"]): Scope }}} */
  create(context) {
    return {
      /** @param node {JSXElement} */
      JSXElement(node) {
        /** @type {Array<{ parent: string, child: string, message?: string, module?: string }>} */
        const requirements = Array.isArray(context.options)
          ? /** @type {Array<{ parent: string, child: string, message?: string, module?: string }>} */ (context.options)
          : []
        if (!requirements) return

        for (const {parent, child, message, module} of requirements) {
          if (getComponentName(node) !== parent) continue
          if (
            module &&
            !isImportedFrom(new RegExp(module), {name: parent}, context.sourceCode.getScope(node.openingElement))
          )
            continue
          if (!hasChild(node, child)) {
            context.report({
              // @ts-expect-error expecting Node type
              node,
              data: {
                parent,
                child,
                message: message ? `, ${message}` : '',
              },
              messageId: 'requireChildren',
            })
          }
        }
      },
    }
  },
}
