const orderHash = require('../helpers/order-hash')

const REQUIRED_SCRIPTS = ['tsc', 'lint', 'test', 'stylelint']
const SCRIPTS = {
  tsc: 'tsc',
  lint: 'eslint . --cache',
  test: 'jest',
  stylelint: 'stylelint --aei --rd "**/*.css"',
}

// these are utility packages that use jest but also need exports from @github-ui/tests
const EXCEPTIONS = [
  'ui/packages/mock-fetch',
  'ui/packages/ref-selector',
  'ui/packages/storybook',
  'ui/packages/ui-packages-tooling',
  'test/js',
]

module.exports = {
  meta: {
    type: 'suggestion',
    docs: {
      description: `Monorepo packages require (${REQUIRED_SCRIPTS.join(',')}) scripts in package.json`,
    },
    schema: [],
    fixable: 'code',
    messages: {
      missingScript: 'Missing required scripts "{{script}}" in package.json',
    },
  },

  create(context) {
    return {
      'Program:exit': node => {
        const {text} = context.sourceCode
        const packageJson = JSON.parse(text)
        const missingScripts = []

        // Check if the file is in an exception directory
        const isException = EXCEPTIONS.some(exception => context.getFilename().includes(exception))

        for (const script of REQUIRED_SCRIPTS) {
          if (!packageJson.scripts || !packageJson.scripts[script]) {
            missingScripts.push(script)
            if (!packageJson.scripts) packageJson.scripts = {}
            packageJson.scripts[script] = SCRIPTS[script]
          }
        }

        // Adjust the test script if @github-ui/tests is in devDependencies
        if (
          packageJson.devDependencies &&
          packageJson.devDependencies['@github-ui/tests'] &&
          packageJson.scripts.test !== 'ui-test' &&
          !isException
        ) {
          missingScripts.push('test')
          packageJson.scripts.test = 'ui-test'
        }

        if (missingScripts.length > 0) {
          packageJson.scripts = orderHash(packageJson.scripts)

          context.report({
            node,
            messageId: 'missingScript',
            data: {script: missingScripts.sort().join(', ')},
            fix: fixer => fixer.replaceText(node, JSON.stringify(packageJson, null, 2)),
          })
        }
      },
    }
  },
}
