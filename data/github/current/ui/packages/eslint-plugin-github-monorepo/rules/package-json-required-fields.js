const {basename, dirname} = require('path')
const isPublishedPackage = require('../helpers/is-published-package')

const REQUIRED_FIELDS = {
  name: {
    validate: (val, path) => val === `@github-ui/${basename(path)}`,
    fix: (fixer, packageJson, node, path) => {
      packageJson.name = `@github-ui/${basename(path)}`

      return fixer.replaceText(node, JSON.stringify(packageJson, null, 2))
    },
    message: path => `Expected the package to be named @github-ui/${basename(path)}`,
  },
  description: {
    validate: val => Boolean(val),
    message: () => 'Packages must have a description',
  },
  private: {
    validate: (val, path) => (isPublishedPackage(path) ? !val : val === true),
    fix: (fixer, packageJson, node, path) => {
      if (isPublishedPackage(path)) {
        delete packageJson.private
      } else {
        packageJson.private = true
      }
      return fixer.replaceText(node, JSON.stringify(packageJson, null, 2))
    },
    message: path =>
      isPublishedPackage(path)
        ? 'Expected "private" field to be false for packages listed in ui/packages/eslint-plugin-github-monorepo/published-packages.js'
        : 'Expected "private" field to be true for packages not listed in ui/packages/eslint-plugin-github-monorepo/published-packages.js',
  },
  version: {
    validate: (val, path) => (isPublishedPackage(path) ? !!val : !val),
    fix: (fixer, packageJson, node, path) => {
      if (isPublishedPackage(path)) {
        packageJson.version = packageJson.version || '0.1.0'
      } else {
        delete packageJson.version
      }
      return fixer.replaceText(node, JSON.stringify(packageJson, null, 2))
    },
    message: path =>
      isPublishedPackage(path)
        ? 'Expected "version" field to exist for packages listed in ui/packages/eslint-plugin-github-monorepo/published-packages.js'
        : 'Expected "version" field to be undefined for packages not listed in ui/packages/eslint-plugin-github-monorepo/published-packages.js',
  },
}

module.exports = {
  meta: {
    type: 'suggestion',
    docs: {
      description: `Monorepo packages require (${Object.keys(REQUIRED_FIELDS).join(',')}) in package.json`,
    },
    schema: [
      {
        type: 'object',
        properties: {
          skip: {
            type: 'array',
          },
        },
        additionalProperties: false,
      },
    ],
    fixable: 'code',
  },

  create(context) {
    return {
      'Program:exit': node => {
        const {text} = context.sourceCode
        const path = dirname(context.getPhysicalFilename())
        const skip = context.options?.[0]?.skip ?? []

        const packageJson = JSON.parse(text)
        for (const [field, options] of Object.entries(REQUIRED_FIELDS)) {
          if (skip.includes(field)) continue

          if (!options.validate(packageJson[field], path)) {
            context.report({
              node,
              message: options.message(path),
              fix: fixer => options.fix && options.fix(fixer, packageJson, node, path),
            })
          }
        }
      },
    }
  },
}
