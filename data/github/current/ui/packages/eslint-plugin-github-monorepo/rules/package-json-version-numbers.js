const {basename, dirname} = require('path')
const {managedDependencies} = require('@github-ui/managed-dependencies')

/**
 * This lint rule ensures that all dependencies in package.json files are either:
 * 1. Internal dependencies that use "*" as the version number (eg "@github-ui/react-core": "*")
 * 2. External dependencies that use a specific version number (eg "glob": "7.1.6")
 * 3. External dependencies that are managed by another package and use "*" as the version number (eg "react": "*")
 */

// This list should only be added to if we are _intentionally_ using a different version of a dependency
const exemptDependencies = {
  '@github-ui/react-next': ['react', 'react-dom', 'react-is'],
  '@github-ui/react-router': ['react-router', 'react-router-dom'],
}

function isManagedDependency(dependencyName, currentPackageName) {
  const owningPackage = managedDependencies[dependencyName]
  return owningPackage && owningPackage !== currentPackageName
}

function isExemptDependency(dependencyName, currentPackageName) {
  const exemptPackages = exemptDependencies[currentPackageName]
  return exemptPackages && exemptPackages.includes(dependencyName)
}

module.exports = {
  meta: {
    type: 'suggestion',
    docs: {
      description: `Ensure external dependencies have a specific version number, and internal dependencies use "*"`,
    },
    messages: {
      packageJsonVersionNumbers:
        'Dependency "{{dependencyName}}" in "{{keyValue}}" is an external dependency and needs a specific version number',
    },
    schema: [],
    fixable: 'code',
  },

  create(context) {
    const fileName = context.getFilename()
    const currentPackageName = `@github-ui/${basename(dirname(fileName))}`

    return {
      Property(node) {
        const {key, value} = node

        if ((key.value !== 'dependencies' && key.value !== 'devDependencies') || value.type !== 'ObjectExpression') {
          return
        }

        for (const prop of value.properties) {
          const dependencyName = prop.key.value

          if (isExemptDependency(dependencyName, currentPackageName) || prop.value.type !== 'Literal') {
            continue
          }

          // Internal/managed dependencies should always use "*"
          if (dependencyName.startsWith('@github-ui/') || isManagedDependency(dependencyName, currentPackageName)) {
            if (prop.value.value !== '*') {
              context.report({
                node: prop.value,
                data: {
                  dependencyName,
                  keyValue: key.value,
                },
                messageId: 'packageJsonVersionNumbers',
                fix: fixer => fixer.replaceText(prop.value, '"*"'),
              })
            }
          } else if (prop.value.value === '*') {
            // Any other dependency should use a specific version number
            context.report({
              node: prop.value,
              data: {
                dependencyName,
                keyValue: key.value,
              },
              messageId: 'packageJsonVersionNumbers',
            })
          }
        }
      },
    }
  },
}
