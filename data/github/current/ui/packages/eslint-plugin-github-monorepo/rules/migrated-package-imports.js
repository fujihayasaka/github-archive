const path = require('node:path')

const migratedFiles = {
  //---- start of migrated files ----
  'app/assets/modules/alloy/index': '@github-ui/alloy-entry',
  'app/assets/modules/example-file': '@github-ui/example-package',
  'app/assets/modules/github/behaviors/avatar-reset-text': '@github-ui/avatar-reset-element',
  'app/assets/modules/github/include-fragment-element-hacks': '@github-ui/include-fragment',
  //---- end of migrated files ----
}
const rootPath = path.resolve(__dirname, '../../../../')

module.exports = {
  meta: {
    type: 'error',
    docs: {
      description: 'This file has been moved to a new UI package. Run the auto-fixer to update the import path.',
    },
    messages: {
      migratedPackageImport:
        'The file {{relativePath}} has been moved to {{newPath}}. Please import that package instead.',
    },
    schema: [],
    fixable: 'code',
  },

  create(context) {
    return {
      ImportDeclaration(node) {
        const importedValue = node.source.value

        // ignore non-relative imports
        if (!importedValue.startsWith('.')) return

        // get the path from the root
        const filename = context.filename ?? context.getFilename()
        const fullPath = path.join(path.dirname(filename), importedValue)
        const relativePath = path.relative(rootPath, fullPath)
        const relativePathWithoutExtension = relativePath.split('.')[0]

        // check if the file is in the migratedFiles list
        const newPath = migratedFiles[relativePathWithoutExtension]

        if (newPath) {
          return context.report({
            node: node.source,
            messageId: 'migratedPackageImport',
            data: {
              relativePath,
              newPath,
            },
            fix: fixer => {
              return fixer.replaceText(node.source, `'${newPath}'`)
            },
          })
        }
      },
    }
  },
}
