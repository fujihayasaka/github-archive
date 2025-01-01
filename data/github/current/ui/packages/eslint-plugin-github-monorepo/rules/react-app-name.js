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
    hasSuggestions: true,
  },

  create(context) {
    const fileName = context.getFilename()
    const packageNameMatch = fileName.match(packageNameMatcher)
    if (!packageNameMatch) return {}

    return {
      CallExpression(node) {
        const {callee, arguments} = node
        if (callee.type === 'Identifier' && callee.name === 'registerReactAppFactory') {
          const firstArg = arguments[0]?.value
          const appName = typeof firstArg === 'string' ? firstArg : null

          const packageName = packageNameMatch[1]

          if (appName === packageName) return

          context.report({
            node: arguments[0],
            message: 'React apps must have the same name as the package they are registered in.',
            suggest: [
              {
                fix: fixer => fixer.replaceText(arguments[0], `'${packageName}'`),
                desc: 'Rename the app to match the package name.',
              },
            ],
          })
        }
      },
    }
  },
}

module.exports = rule
