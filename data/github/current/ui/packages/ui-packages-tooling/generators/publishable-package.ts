import type {NodePlopAPI} from 'plop'
import {fullPathFromRoot, globFromRoot, relativePathFromRoot} from '@github-ui/client-build-tools/path-utils'
import path from 'node:path'
import type {AddLineToFileConfig} from './actions/add-line-to-file.ts'
import {readFileSync} from 'node:fs'
import {commonActions, templatePath} from './common.ts'

const publishedPackageFilePath = `${fullPathFromRoot(
  'ui/packages/eslint-plugin-github-monorepo/published-packages.js',
)}/`

interface Package {
  folderPath: string
  name: string
  details?: {
    version?: string
    private?: boolean
    exports: {[key: string]: string}
    main?: string
  }
}

interface FolderChoice {
  name: string
  description: string
  value: Package
}
let foldersToUpgrade: FolderChoice[] | null = null

function createFolderChoice(packageJsonPath: string): FolderChoice {
  const packageJsonText = readFileSync(packageJsonPath, 'utf8')
  const packageJson = JSON.parse(packageJsonText)
  const folderPath = path.dirname(packageJsonPath)
  const folderName = path.basename(folderPath)

  return {
    name: folderName,
    value: {
      folderPath,
      name: folderName,
      details: {
        version: packageJson.version,
        private: packageJson.private,
        exports: packageJson.exports,
        main: packageJson.main,
      },
    },
    description: relativePathFromRoot(packageJsonPath),
  }
}

/**
 * This prompt provides an auto-complete for selecting a folder to upgrade from ui/packages
 */
const packagesToUpgradePrompt = {
  type: 'autocomplete',
  name: 'package',
  message: 'Package to Upgrade:',
  source: (_: unknown, input: string) => {
    if (!foldersToUpgrade) {
      foldersToUpgrade = globFromRoot('ui/packages/**/package.json')
        .map(createFolderChoice)
        .filter(f => {
          const isPrivate = f?.value?.details?.private
          const hasVersion = f?.value?.details?.version
          // Assume folder is published if it does not have `private: true` or has a `version`
          return isPrivate && !hasVersion
        })
    }

    if (!input) {
      return foldersToUpgrade
    }

    return foldersToUpgrade.filter(file => file.name.includes(input))
  },
}

export function registerPublishablePackageGenerator(plop: NodePlopAPI) {
  plop.setGenerator('Upgrade a ui/package to be publishable', {
    description: 'Add configurations to be able to publish a UI package',
    prompts: [packagesToUpgradePrompt],
    actions: answers => {
      if (!answers) {
        throw new Error('No answers supplied')
      }
      const {folderPath, name: folderName} = answers.package as Package
      const packageJsonPath = path.join(folderPath, 'package.json')

      const actions = [
        // Add package to published-package file
        {
          type: 'addLineToFile',
          line: `  '${folderName}',`,
          path: publishedPackageFilePath,
          sectionStart: '  //---- start of published packages ----',
          sectionEnd: `  //---- end of published files ----`,
        } satisfies AddLineToFileConfig,

        // Create tsconfig.build.json
        {
          type: 'add',
          path: path.join(folderPath, 'tsconfig.build.json'),
          templateFile: templatePath('tsconfig.build.json.hbs'),
        },

        /*
         * Package.json edits
         */
        // Remove private field
        {
          type: 'replaceInFile',
          path: path.join(folderPath, 'package.json'),
          matcher: new RegExp(`[,]?\n  "private": true[,]?`, 'ms'),
          newValue: '',
        },
        // Add version field in between `name` and `description` fields
        {
          type: 'addLineToFile',
          line: `  "version": "1.0.0",\n`,
          path: packageJsonPath,
          sectionStart: `  "name": "\\S+",`,
          sectionEnd: `?  "description": "(\\\\"|[^"])*",`,
        } satisfies AddLineToFileConfig,
        // Add type field in between `main` and `exports` fields
        {
          type: 'addLineToFile',
          line: `  "type": "module",\n`,
          path: packageJsonPath,
          sectionStart: `  "main": "(\\\\"|[^"])*",`,
          sectionEnd: `?  "exports": {`,
        } satisfies AddLineToFileConfig,

        // Add a build script to package.json, which compiles the package for publishing
        {
          type: 'addLineToFile',
          line: `    "build": "node ../publish-packages/scripts/build.js",
    "build:publish": "../publish-packages/scripts/publish",
    "build:types": "tsc --project ./tsconfig.build.json",`,
          path: packageJsonPath,
          sectionStart: '  "scripts": {',
          sectionEnd: `  },\n  "dependencies": {`,
        } satisfies AddLineToFileConfig,

        // Run `npm install` in the package directory
        commonActions.npmInstall,
        () =>
          `Next steps:

  - Restart ESLint Server to update the linter's published packages

      Open the VSCode Command Palette (Ctrl + Shift + P or View > Command Palette). Search and select 'ESLint: Restart ESLint Server'

  - Run the following command in the package directory to publish

      npm run build:publish
`,
      ]

      return actions
    },
  })
}
