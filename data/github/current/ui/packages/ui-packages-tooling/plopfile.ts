import {addLineToFile} from './generators/actions/add-line-to-file.ts'
import {openFile} from './generators/actions/open-file.ts'
import {runCommand} from './generators/actions/run-command.ts'
import {replaceInFile} from './generators/actions/replace-in-file.ts'
import {registerReactDataRouterAppGenerator} from './generators/react-data-router-app.ts'
import {registerReactAppGenerator} from './generators/react-app.ts'
import {registerReactPartialGenerator} from './generators/react-partial.ts'
import {registerReactComponentGenerator} from './generators/react-component.ts'
import {registerReactHookGenerator} from './generators/react-hook.ts'
import {registerCatalystComponentGenerator} from './generators/catalyst-component.ts'
import {registerBuildScriptGenerator} from './generators/build-script.ts'
import {registerBasicPackageGenerator} from './generators/basic-package.ts'
import {registerMigratePackageGenerator} from './generators/migrate-package.ts'
import {registerPublishablePackageGenerator} from './generators/publishable-package.ts'
import type {NodePlopAPI} from 'plop'
import {registerMigrateCssModulesGenerator} from './generators/migrate-css.ts'

export default async function plopConfig(plop: NodePlopAPI) {
  plop.setActionType('addLineToFile', addLineToFile)
  plop.setActionType('runCommand', runCommand)
  plop.setActionType('openFile', openFile)
  plop.setActionType('replaceInFile', replaceInFile)

  const {default: autocomplete} = await import('inquirer-autocomplete-prompt')
  plop.setPrompt('autocomplete', autocomplete)

  registerReactDataRouterAppGenerator(plop)
  registerReactPartialGenerator(plop)
  registerReactComponentGenerator(plop)
  registerReactHookGenerator(plop)
  registerCatalystComponentGenerator(plop)
  registerBuildScriptGenerator(plop)
  registerBasicPackageGenerator(plop)
  registerPublishablePackageGenerator(plop)
  registerMigratePackageGenerator(plop)
  registerMigrateCssModulesGenerator(plop)
  registerReactAppGenerator(plop)
}
