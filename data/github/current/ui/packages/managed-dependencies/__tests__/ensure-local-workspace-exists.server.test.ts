import {it, describe} from '@github-ui/tests'
import {RuleTester} from 'eslint'
import createRule from '../lint/ensure-local-workspace-exists.mjs'

const ruleTester = new RuleTester({
  languageOptions: {
    ecmaVersion: 2020,
    sourceType: 'module',
  },
})

describe('ensure-local-workspace-exists', () => {
  const rule = createRule(() => new Set(['@github-ui/package-a', '@github-ui/package-b', '@github-ui/package-d']))
  it('reports an error if a dependency is not part of the npm workspace', () => {
    ruleTester.run('ensure-local-workspace-exists', rule, {
      valid: [
        {
          code: `const managedDependencies = { 'package-a': '@github-ui/package-a' };`,
        },
      ],
      invalid: [
        {
          code: `const managedDependencies = { 'package-c': '@github-ui/not-a-valid-package-dude' };`,
          errors: [
            {
              message:
                "'@github-ui/not-a-valid-package-dude' is not part of the npm workspace. Did you mean '@github-ui/package-d'?",
            },
          ],
        },
      ],
    })
  })

  it('does not report an error if all dependencies are part of the npm workspace', () => {
    ruleTester.run('ensure-local-workspace-exists', rule, {
      valid: [
        {
          code: `const managedDependencies = { 'package-a': '@github-ui/package-a', 'package-b': '@github-ui/package-b', 'package-d': '@github-ui/package-d' };`,
        },
      ],
      invalid: [],
    })
  })
})
