// This is adapted from https://github.com/selaux/eslint-plugin-filenames since it's no longer actively maintained

// This rule is based on existing dotcom naming patterns and React conventions. Enforced conventions are:
// - kebab case for .js and .ts files
// - Pascal case for .tsx files
//   - including Index.tsx rather than index.tsx
//   - .tsx hooks files can be prefixed with "use" (e.g. usePagination.tsx)
//
// See tests for example patterns: /__tests__/filename-convention.test.ts

const path = require('path')
const {pascalCase, paramCase: kebabCase} = require('change-case')

const CONVENTIONS = {
  KEBAB: 'kebab case',
  PASCAL: 'Pascal case (or "use" + Pascal case)',
}

/**
 * @type {import('eslint').Rule.RuleModule}
 */
module.exports = {
  meta: {
    type: 'suggestion',
    docs: {
      description: 'ensure .js, .ts, and .tsx file names match dotcom and React community naming conventions.',
      url: 'https://github.com/github/github/blob/master/ui/packages/eslint-plugin-github-monorepo/rules/filename-convention.js',
    },
    schema: false,
    messages: {
      failsConvention:
        "File name '{{base}}' does not match our '{{convention}}' naming convention for {{ext}} files. '{{validName}}' would be a valid file name.",
    },
  },

  create(context) {
    const fileName = context.filename ?? context.getFilename()
    const absoluteFileName = path.resolve(fileName)
    const parsed = path.parse(absoluteFileName)
    const ext = parsed.ext
    const base = parsed.base

    const filetypes = ['.js', '.ts', '.tsx']

    function generateFileName(originalFileName) {
      const parts = originalFileName.split('.')
      const extension = parts[parts.length - 1]
      const operator = extension === 'tsx' ? pascalCase : kebabCase
      const pascalTestRegexp = /^(use)?[A-Z][a-zA-Z0-9]*$/

      const leadingParts = parts[0] === '' ? parts.slice(0, 1) : []
      const [mainPart, ...trailingParts] = parts[0] === '' ? parts.slice(1) : parts

      let validMainPart
      if (operator === pascalCase && pascalTestRegexp.test(mainPart)) {
        validMainPart = mainPart
      } else {
        validMainPart = operator(mainPart)
      }

      const newParts = [...leadingParts, validMainPart, ...trailingParts.map(kebabCase)]
      return newParts.join('.')
    }

    function reportConventionViolation(node, convention, validName) {
      context.report({
        node,
        messageId: 'failsConvention',
        data: {
          base,
          convention,
          ext,
          validName,
        },
      })
    }

    return {
      Program(node) {
        const validName = generateFileName(base)
        const isValid = base === validName

        if (!filetypes.includes(ext)) {
          return
        }

        if (!isValid && (ext === '.js' || ext === '.ts')) {
          reportConventionViolation(node, CONVENTIONS.KEBAB, validName)
        } else if (!isValid && ext === '.tsx') {
          reportConventionViolation(node, CONVENTIONS.PASCAL, validName)
        }
      },
    }
  },
}
