const orderHash = require('../helpers/order-hash')
const REQUIRED_DEV_DEPENDENCIES = ['@github-ui/eslintrc']
const TESTING_DEV_DEPENDENCIES = ['@github-ui/tests', '@github-ui/jest']
const EXCEPTIONS = [
  'ui/packages/mock-fetch',
  'ui/packages/ref-selector',
  'ui/packages/storybook',
  'ui/packages/ui-packages-tooling',
  'test/js',
]

const hangingIndent = (value, depth) =>
  value
    .split('\n')
    .map((l, i) => (i === 0 ? l : `${' '.repeat(depth)}${l}`))
    .join('\n')

module.exports = {
  meta: {
    type: 'suggestion',
    docs: {
      description: `Monorepo packages require (${REQUIRED_DEV_DEPENDENCIES.join(
        ',',
      )}) as dev dependencies, and one of (${TESTING_DEV_DEPENDENCIES.join(',')})`,
    },
    schema: [],
    fixable: 'code',
    messages: {
      missingDependenciesMessage: 'Missing required devDependency {{devDependency}} in package.json',
      extraTestDependencyMessage: `Only one testing devDependency is allowed: (${TESTING_DEV_DEPENDENCIES.join(',')})`,
    },
  },

  create(context) {
    return {
      'Program:exit': node => {
        const {text} = context.sourceCode
        const packageJson = JSON.parse(text)

        const missingDependencies = []
        let hasExtraTestingDevDependency = false

        // Check for missing required dev dependencies
        for (const devDependency of REQUIRED_DEV_DEPENDENCIES) {
          if (!packageJson.devDependencies || !packageJson.devDependencies[devDependency]) {
            missingDependencies.push(devDependency)
          }
        }

        // Check for testing dev dependencies
        const testingDependencies = TESTING_DEV_DEPENDENCIES.filter(
          dep => packageJson.devDependencies && packageJson.devDependencies[dep],
        )

        if (testingDependencies.length === 0) {
          missingDependencies.push(TESTING_DEV_DEPENDENCIES[0])
        } else if (testingDependencies.length > 1) {
          const filePath = context.getFilename()
          if (!EXCEPTIONS.some(exception => filePath.includes(exception))) {
            hasExtraTestingDevDependency = true
          }
        }

        // Handle extra testing dependencies
        if (hasExtraTestingDevDependency) {
          context.report({
            node,
            messageId: 'extraTestDependencyMessage',
            fix: fixer => {
              const lastTestingDependency = TESTING_DEV_DEPENDENCIES[1]
              if (lastTestingDependency) {
                delete packageJson.devDependencies[lastTestingDependency]
                packageJson.devDependencies = orderHash(packageJson.devDependencies)
                return fixer.replaceText(node, hangingIndent(JSON.stringify(packageJson, null, 2), 2))
              }
            },
          })
        }

        // Handle missing dependencies
        if (missingDependencies.length > 0) {
          context.report({
            node,
            messageId: 'missingDependenciesMessage',
            data: {devDependency: missingDependencies.join(', ')},
            fix: fixer => {
              if (!packageJson.devDependencies) packageJson.devDependencies = {}

              for (const dep of missingDependencies) {
                packageJson.devDependencies[dep] = '*'
              }

              packageJson.devDependencies = orderHash(packageJson.devDependencies)
              return fixer.replaceText(node, hangingIndent(JSON.stringify(packageJson, null, 2), 2))
            },
          })
        }
      },
    }
  },
}
