import {buildESLintConfigTree} from './helpers/build-eslintrc-dependency-tree'

const eslintConfigTree = buildESLintConfigTree()

describe('ESLint duplicated rules', () => {
  it('should not allow duplicated rules in child configs', () => {
    const errors: string[] = []
    for (const config of Object.values(eslintConfigTree)) {
      if (!config.parent || !config.rules) continue

      for (const [name, definition] of Object.entries(config.rules)) {
        const extendDefinition = config.extensionRules[name]
        // overriding a rule coming from a `extends`
        if (extendDefinition && extendDefinition !== definition) continue

        for (const ancestor of config.ancestors()) {
          const ancestorDefinition = ancestor.rules[name]

          // found closest parent definition
          if (ancestorDefinition) {
            if (ancestorDefinition === definition) {
              errors.push(
                `ERROR in ${config.path} --- ${name}: ${definition} has already been defined by ${ancestor.path}`,
              )
            }
            break
          }
        }
      }
    }

    expect(errors).toStrictEqual([])
  })
})
