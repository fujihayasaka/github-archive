// @ts-check

const {ESLintUtils, AST_NODE_TYPES} = require('@typescript-eslint/utils')
/** @typedef {import('@typescript-eslint/types').TSESTree.JSXAttribute} JSXAttribute */

module.exports = ESLintUtils.RuleCreator.withoutDocs({
  meta: {
    docs: {
      description:
        'We are discouraging usage of the `useFeatureFlags` hook in favor of `isFeatureEnabled`. As packages are migrated, they can enable this rule to prevent regression.',
    },
    messages: {
      noUseFeatureFlags:
        'Prefer using `isFeatureEnabled` over `useFeatureFlags`. Please refer to https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/overview/#feature-flags-in-the-typescript-front-end for more information.',
    },
    // this is just a suggestion since there is still a use case for useFeatureFlags - when enabling per Organization or Business
    type: 'suggestion',
    schema: [],
  },
  defaultOptions: [],
  create(context) {
    return {
      CallExpression(node) {
        if (
          node.callee.type === AST_NODE_TYPES.Identifier &&
          ['useFeatureFlag', 'useFeatureFlags'].includes(node.callee.name)
        )
          context.report({messageId: 'noUseFeatureFlags', node})
      },
    }
  },
})
