import type {NodePlopAPI} from 'plop'
import {commonPrompts, requiredPrompt} from './common.ts'

export function registerMigrateCssModulesGenerator(plop: NodePlopAPI) {
  plop.setGenerator('Migrate to CSS Modules', {
    description:
      'Migrate code to use CSS modules instead of styled components. This will remove the sx usage and replace it with a CSS modules file.',
    prompts: [
      {
        type: 'list',
        name: 'migrateType',
        message: 'Do you want to run this migration against files, a package, or by service owner?',
        choices: ['files', 'package', 'service owner'],
        validate: requiredPrompt,
      },
      {
        type: 'input',
        name: 'targetFilesOrDirs',
        message: 'Enter the comma-separated list of files or directories to migrate:',
        when: answers => answers.migrateType === 'files',
        validate: requiredPrompt,
      },
      {
        ...commonPrompts.package,
        name: 'packageName',
        message: 'Enter the package name (within ui/packages) to migrate:',
        when: answers => answers.migrateType === 'package',
        validate: requiredPrompt,
      },
      {
        ...commonPrompts.team,
        name: 'serviceOwner',
        message: 'Enter the service owner (snake-case) whose files to migrate:',
        when: answers => answers.migrateType === 'service owner',
        validate: requiredPrompt,
      },
      {
        type: 'confirm',
        name: 'runLinters',
        message: 'Do you want to run linters after migration? For files or service owner, it may take a while.',
        default: true,
      },
      {
        type: 'input',
        name: 'targetComponents',
        message: 'Enter the comma-separated list of components to migrate, leave empty to migrate all:',
      },
    ],
    actions: answers => {
      if (!answers) {
        throw new Error('No answers supplied')
      }

      const args = ['--skip-warning']
      if (answers.runLinters) {
        args.push('-l')
      } else {
        args.push('--skip-lint')
      }

      if (answers.migrateType === 'files') {
        args.push(`-f`)
        args.push(answers.targetFilesOrDirs)
      } else if (answers.migrateType === 'package') {
        args.push(`-p`)
        args.push(answers.packageName)
      } else if (answers.migrateType === 'service owner') {
        args.push(`-s`)
        args.push(answers.serviceOwner)
      }

      if (answers.targetComponents) {
        args.push(`-c`)
        args.push(answers.targetComponents)
      }

      const actions = []
      actions.push({
        type: 'runCommand',
        cmd: 'script/migrate-css-modules',
        args,
        ignoreFailure: true,
        showStdout: true,
      })

      return actions
    },
  })
}
