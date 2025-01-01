const packageNameMatcher = /\/ui\/packages\/([^/]+)/

/**
 * @type {import('eslint').Rule.RuleModule}
 */
const rule = {
  meta: {
    type: 'problem',
    docs: {
      description: 'React Apps must have the same name as the package they are in.',
    },
    messages: {
      reactAppName: 'React apps must have the same name as the package they are registered in.',
      suggestionMessage: 'Rename the app to match the package name.',
    },
    hasSuggestions: true,
  },

  create(context) {
    const fileName = context.getFilename()
    const packageNameMatch = fileName.match(packageNameMatcher)
    if (!packageNameMatch) return {}

    return {
      CallExpression(node) {
        const {callee, arguments: args} = node
        const packageName = packageNameMatch[1]

        // Check for `registerNavigatorApp` calls
        if (callee.type === 'Identifier' && callee.name === 'registerNavigatorApp') {
          const firstArg = args[0]?.value
          const appName = typeof firstArg === 'string' ? firstArg : null

          if (appName !== packageName) {
            context.report({
              node: args[0],
              messageId: 'reactAppName',
              suggest: [
                {
                  fix: fixer => fixer.replaceText(args[0], `'${packageName}'`),
                  messageId: 'suggestionMessage',
                },
              ],
            })
          }
        }

        // Check for `DataRouterApplicationBuilder.create` calls
        if (
          callee.type === 'MemberExpression' &&
          callee.object.type === 'Identifier' &&
          callee.object.name === 'DataRouterApplicationBuilder' &&
          callee.property.type === 'Identifier' &&
          callee.property.name === 'create'
        ) {
          const firstArg = args[0]?.value
          const appName = typeof firstArg === 'string' ? firstArg : null

          if (appName !== packageName) {
            context.report({
              node: args[0],
              messageId: 'reactAppName',
              suggest: [
                {
                  fix: fixer => fixer.replaceText(args[0], `'${packageName}'`),
                  messageId: 'suggestionMessage',
                },
              ],
            })
          }
        }
      },
    }
  },
}

module.exports = rule
