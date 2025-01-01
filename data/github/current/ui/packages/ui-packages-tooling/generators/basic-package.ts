import type {NodePlopAPI} from 'plop'
import {
  commonActions,
  commonPrompts,
  getDependencyJsonContent,
  getScriptsJsonContent,
  packagePath,
  standardDevDependencies,
  standardPackageActions,
  standardScripts,
  templatePath,
} from './common.ts'

export function registerBasicPackageGenerator(plop: NodePlopAPI) {
  plop.setGenerator('Basic Package', {
    description: 'Add a generic UI package',
    prompts: [commonPrompts.packageName, commonPrompts.description, commonPrompts.service],
    actions: answers => {
      if (!answers) {
        throw new Error('No answers supplied')
      }

      answers.createEntry = false
      answers.scriptsJson = getScriptsJsonContent(standardScripts)
      answers.devDependenciesJson = getDependencyJsonContent(standardDevDependencies)

      const actions = [
        commonActions.mainFile,
        {
          type: 'add',
          path: packagePath('__tests__/{{packageName}}.browser.test.ts'),
          templateFile: templatePath('browser.test.ts.hbs'),
        },
        ...standardPackageActions,
        commonActions.restartJsAssets,
        () => `Next steps:

- \`npm run test:watch\` - this will start the tests and run only the files which have changed
- Commit changes and run \`script/generate-service-files.rb\``,
      ]

      return actions
    },
  })
}
