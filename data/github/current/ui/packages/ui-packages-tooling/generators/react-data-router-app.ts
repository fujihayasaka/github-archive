import {camelCase, paramCase, pascalCase, snakeCase} from 'change-case'
import type {NodePlopAPI} from 'plop'
import {
  commonActions,
  commonPrompts,
  getDependencyJsonContent,
  getScriptsJsonContent,
  validRoutePath,
  requiredPrompt,
  standardDevDependencies,
  standardPackageActions,
  standardScripts,
  templatePath,
} from './common.ts'

export function registerReactDataRouterAppGenerator(plop: NodePlopAPI) {
  plop.setGenerator('React App', {
    description:
      'Create a React App. File a React Use Case issue https://github.com/github/react-lang/issues/new?template=react-use-case.md or reach out in #react before using.',
    prompts: [
      {
        ...commonPrompts.packageName,
        message: 'App name:',
      },
      commonPrompts.description,
      commonPrompts.service,
      {
        type: 'input',
        name: 'routePath',
        message: 'Initial route path (e.g. /pulls/:pr_number/top-comments):',
        validate: validRoutePath,
      },
      {
        type: 'input',
        name: 'routeComponent',
        message: 'Initial route name (e.g. TopComments):',
        validate: requiredPrompt,
        filter: pascalCase,
      },
      {
        ...commonPrompts.ssr,
        message: 'Is this app going to be Server Side Rendered?',
      },
    ],
    actions: answers => {
      if (!answers) {
        throw new Error('No answers supplied')
      }

      answers.scriptsJson = getScriptsJsonContent(standardScripts)
      answers.dependenciesJson = getDependencyJsonContent({
        '@github-ui/react-core': '*',
        react: '*',
      })

      const extraDevDependencies: Record<string, string> = {
        '@testing-library/react': '*',
      }

      if (answers.enableSSR) extraDevDependencies['@github-ui/ssr-test-utils'] = '*'

      answers.devDependenciesJson = getDependencyJsonContent({
        ...standardDevDependencies,
        ...extraDevDependencies,
      })

      answers.createEntry = true
      answers.appNameVariable = `${camelCase(answers.packageName)}App`
      answers.appBuilderName = `${answers.appNameVariable}Builder`
      answers.routeVariable = `${camelCase(answers.routeComponent)}Route`
      answers.routeFileName = paramCase(answers.routeVariable)
      answers.payloadType = `${answers.routeComponent}Response`
      answers.mockDataFn = `get${pascalCase(answers.routeVariable)}Payload`

      const ssrSkip = () => {
        if (answers.enableSSR) return false

        return 'Skipping since SSR is disabled'
      }

      const actions = [
        commonActions.entry,
        {
          ...commonActions.ssrEntry,
          skip: ssrSkip,
        },
        {
          type: 'addMany',
          destination: '../{{packageName}}',
          base: templatePath('react-data-router-app'),
          templateFiles: answers.enableSSR
            ? templatePath('react-data-router-app/**/*')
            : templatePath('react-data-router-app/**/!(*SSR)*'), // skip SSR test
        },
        ...standardPackageActions,
        commonActions.restartJsAssets,
        commonActions.restartAlloyAssets,
        (data: Record<string, string>) =>
          `Next steps:

  - Integrate this app into a Rails controller
    - Find or create the matching controller (./app/controllers/${snakeCase(data.packageName!)}_controller.rb)
    - In the desired controller action, add the following code:
        render_react_app(
          payload: { someField: "A message from Rails!" },
          title: "${data.routeComponent}"
        )
  - Visit http://github.localhost${data.routePath}
  - \`npm run test:watch\` - this will start the tests and run only the files which have changed
  - Commit changes and run \`script/generate-service-files.rb\`
        `,
      ]

      return actions
    },
  })
}
