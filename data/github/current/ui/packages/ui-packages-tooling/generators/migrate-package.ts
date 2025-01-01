import type {NodePlopAPI} from 'plop'
import {
  commonActions,
  commonPrompts,
  getDependencyJsonContent,
  getScriptsJsonContent,
  standardDevDependencies,
  standardPackageActions,
  standardScripts,
} from './common.ts'
import {globFromRoot, fullPathFromRoot, relativePathFromRoot} from '@github-ui/client-build-tools/path-utils'
import {resolveImports, __abortWatchers} from '@github-ui/resolve-imports'
import {isManagedDependency} from '@github-ui/managed-dependencies'
import path from 'node:path'
import {listMatchingServices, getServiceOwnerForFile} from './prompts/available-services.ts'
import type {AddLineToFileConfig} from './actions/add-line-to-file.ts'
import {getReferencingFiles} from './migration/referencing-files.ts'

interface File {
  fullPath: string
  name: string
  details?: {
    files: string[]
    dependencies: Record<string, string>
    devDependencies: Record<string, string>
    referencingFiles: string[]
  }
}

interface FileChoice {
  name: string
  description: string
  value: File
}
let filesToMigrate: FileChoice[] | null = null
const appAssetsModulesPath = `${fullPathFromRoot('app/assets/modules')}/`

function createFileChoice(fullPath: string): FileChoice {
  const name = fullPath.replace(appAssetsModulesPath, '')
  return {
    name,
    value: {fullPath, name},
    description: relativePathFromRoot(fullPath),
  }
}

function pathWithoutExtension(filePath: string) {
  const parts = filePath.split('.')
  return parts.slice(0, parts.length - 1).join('.')
}

function getDependencyInfo(
  dependency: string,
  packageLock: {default: {packages: Record<string, {version: string; dev?: boolean}>}},
) {
  // monorepo and managed dependencies use * for their version
  if (dependency.startsWith('@github-ui') || isManagedDependency(dependency)) {
    return {
      dev: false,
      version: '*',
    }
  }

  // get the true version from the package-lock
  const packageProperties = packageLock.default.packages[`node_modules/${dependency}`]
  const version = packageProperties?.version
  return {
    dev: packageProperties?.dev,
    version: version || '*',
  }
}

/**
 * This prompt allows the user to select which browser tests to migrate.
 * It will be manipulated by the fileToMigratePrompt validate step once a file is selected.
 */
interface TestFile {
  relativePath: string
  dependencies: Record<string, string>
}
interface TestFileChoice {
  name: string
  checked: boolean
  value: TestFile
}
const browserTestsPrompt = {
  type: 'checkbox',
  name: 'browserTests',
  message: 'Select related browser tests to migrate',
  choices: [] as TestFileChoice[],
}

/**
 * Custom package name prompt, allowing us to override the default value once a file is selected
 */
const packageNamePrompt = {
  ...commonPrompts.packageName,
  default: '', // to be overridden
}

/**
 * This prompt provides an auto-complete for selecting a file to migrate from app/assets/modules
 * It also has an async validation step which resolves all of the imports for the selected file.
 * This resolution needs to be done here because we don't have another opportunity for an async call
 * before we need to generate the actions for the plop template.
 */
let lastSelectedFile: File | null = null
const fileToMigratePrompt = {
  type: 'autocomplete',
  name: 'file',
  message: 'File to Migrate:',
  source: (_: unknown, input: string) => {
    if (!filesToMigrate) {
      filesToMigrate = globFromRoot('app/assets/modules/**/*.{ts,tsx}')
        .filter(file => !file.includes('__tests__')) // tests don't need to be migrated individually
        .map(createFileChoice)
    }

    if (!input) {
      return filesToMigrate
    }

    return filesToMigrate.filter(file => file.name.includes(input))
  },
  transformer: (input: string) => {
    console.log('Transforming:', input)
    return input
  },
  validate: async (choice: FileChoice) => {
    // Pre-load the imports for the selected file
    const fullPathToMigrate = choice.value.fullPath
    const resolvedImports = await resolveImports(fullPathToMigrate)
    const packageLock = await import(`${fullPathFromRoot('package-lock.json')}`, {with: {type: 'json'}})
    const dependencies: Record<string, string> = {}
    const devDependencies: Record<string, string> = {}
    const files = new Set(resolvedImports.files)
    const referencingFiles = await getReferencingFiles(fullPathToMigrate)

    for (const dependency of resolvedImports.dependencies) {
      const {dev, version} = getDependencyInfo(dependency, packageLock)
      if (dev) {
        devDependencies[dependency] = version
      } else {
        dependencies[dependency] = version
      }
    }

    // Migrate ssr-entry.ts files if they exist
    for (const referencingFile of referencingFiles.filter(file => file.endsWith('ssr-entry.ts'))) {
      files.add(referencingFile)
      referencingFiles.splice(referencingFiles.indexOf(referencingFile), 1)
    }

    // Migrate related tests and Storybook stories
    for (const file of files) {
      const allReferencingFiles = await getReferencingFiles(file)

      // Find tests which reference any file being migrated
      const testFiles = allReferencingFiles.filter(
        referencingFile => referencingFile.includes('__tests__') || referencingFile.includes('.stories.'),
      )
      for (const testFile of testFiles) {
        // Avoid traversing test files multiple times
        if (files.has(testFile)) {
          continue
        }

        files.add(testFile)
        referencingFiles.splice(referencingFiles.indexOf(testFile), 1)

        // The test file may import help files, so we need to traverse those as well
        const testImports = await resolveImports(fullPathFromRoot(testFile))
        for (const testImport of testImports.files) {
          files.add(testImport)
        }

        // Add the test dependencies as dev dependencies
        for (const dependency of testImports.dependencies) {
          if (dependencies[dependency] || devDependencies[dependency]) {
            continue
          }

          const {version} = getDependencyInfo(dependency, packageLock)
          devDependencies[dependency] = version
        }
      }
    }

    // Ensure all child files are not imported directly from outside the files being migrated
    const childFiles = [...files].filter(file => fullPathFromRoot(file) !== fullPathToMigrate)
    const parentDirectory = path.dirname(relativePathFromRoot(fullPathToMigrate))
    const childReferences: Record<string, string[]> = {}
    const childrenInDifferentDirectory: string[] = []
    for (const childFile of childFiles) {
      const filesReferencingChild = await getReferencingFiles(childFile)
      for (const referencingFile of filesReferencingChild) {
        if (!files.has(referencingFile) && !referencingFile.startsWith('test/')) {
          childReferences[childFile] ||= []
          childReferences[childFile].push(referencingFile)
        }
      }

      if (!path.dirname(childFile).startsWith(parentDirectory)) {
        childrenInDifferentDirectory.push(childFile)
      }
    }
    if (Object.keys(childReferences).length) {
      return `Child files are being referenced from outside the files being migrated. Please migrate each of these to their own package: ${Object.entries(
        childReferences,
      ).map(([childFile, filesReferencingChild]) => {
        return `\n - ${childFile} is referenced by: ${filesReferencingChild.map(file => `\n   - ${file}`).join('')}`
      })}`
    }

    // If any child files are in a different directory, migration will fail
    if (childrenInDifferentDirectory.length) {
      return `Child files are in a different directory, which breaks standard migration. Consider restructuring these files, or migrating them to their own package.

Base Directory:
  - ${parentDirectory}

Child Files In Different Directory:
${childrenInDifferentDirectory.map(file => `  - ${file}`).join('\n')}
`
    }

    // Store the resolved import details for use in actions
    choice.value.details = {
      files: [...files],
      dependencies,
      devDependencies,
      referencingFiles,
    }
    lastSelectedFile = choice.value

    // Ensure watchers don't continue running, or else plop won't exit
    __abortWatchers()

    // Update the browser tests prompt with the list of related tests
    const referencingTestFiles = referencingFiles.filter(file => file.startsWith('test/'))
    if (referencingTestFiles.length) {
      for (const testFile of referencingTestFiles) {
        const {files: importedFiles, dependencies: testDependencies} = await resolveImports(fullPathFromRoot(testFile))

        // If the test references files other than the one being migrated, we want the user to verify it is indeed for this package
        const referencesOtherFiles = importedFiles.some(
          importedFile => fullPathFromRoot(importedFile) !== fullPathToMigrate && !importedFile.startsWith('test/'),
        )
        const prefix = referencesOtherFiles ? '👀' : '✨'

        browserTestsPrompt.choices.push({
          name: `${prefix} ${testFile}`,
          value: {
            relativePath: testFile,
            dependencies: testDependencies
              .filter(dep => !dependencies[dep]) // ignore dependencies from the file being migrated
              .reduce((acc, dep) => ({...acc, [dep]: getDependencyInfo(dep, packageLock).version}), {}),
          },
          checked: !referencesOtherFiles,
        })
      }
    } else {
      browserTestsPrompt.message = 'No related browser tests found. Press enter to continue.'
    }

    // Update the default package name. Use directory name for index files, otherwise use the file name
    const originalFileName = path.parse(fullPathToMigrate).name
    const defaultPackageName =
      originalFileName === 'index' ? path.parse(path.dirname(fullPathToMigrate)).name : originalFileName
    packageNamePrompt.default = defaultPackageName

    return true
  },
}

const fileServiceOwnerPrompt = {
  ...commonPrompts.service,
  source: (_: unknown, input: string) => {
    const autoDetectedService = lastSelectedFile
      ? getServiceOwnerForFile(relativePathFromRoot(lastSelectedFile.fullPath))
      : null
    const services = listMatchingServices(input)

    if (input || !autoDetectedService) {
      return services
    }

    return [
      {
        name: `${autoDetectedService} (auto-detected from SERVICEOWNERS)`,
        value: autoDetectedService,
      },
      ...services.map(name => ({name, value: name})),
    ]
  },
}

export function registerMigratePackageGenerator(plop: NodePlopAPI) {
  plop.setGenerator('Migrate app/assets/modules Files', {
    description: 'Migrate one or more files from app/assets/modules to a new package',
    prompts: [
      fileToMigratePrompt,
      packageNamePrompt,
      commonPrompts.description,
      fileServiceOwnerPrompt,
      browserTestsPrompt,
    ],
    actions: answers => {
      if (!answers) {
        throw new Error('No answers supplied')
      }

      const browserTests = answers.browserTests as TestFile[]
      const {fullPath, details, name: pathFromAppAssetModules} = answers.file as File

      if (!details) {
        throw new Error(`Imports were not resolved for file ${fullPath}`)
      }

      const {files, dependencies, devDependencies, referencingFiles} = details
      const parsedPath = path.parse(fullPath)
      answers.mainFileName = parsedPath.base
      answers.entryFile = parsedPath.name
      answers.scriptsJson = getScriptsJsonContent(standardScripts)
      answers.dependenciesJson = getDependencyJsonContent(dependencies)
      answers.devDependenciesJson = getDependencyJsonContent({
        ...standardDevDependencies,
        ...devDependencies,
        ...browserTests.reduce((acc, browserTest) => ({...acc, ...browserTest.dependencies}), {}),
      })
      const packageName = answers.packageName

      console.log(`Migrating ${relativePathFromRoot(fullPath)} to @github-ui/${packageName}`)
      console.log(`Moving ${files.length} file(s):`)
      console.log(files.map(file => `  - ${file}`).join('\n'))
      console.log('Dependencies:', dependencies)
      console.log('Dev Dependencies:', devDependencies)

      if (referencingFiles.length) {
        console.log(`Found ${referencingFiles.length} file(s) referencing ${relativePathFromRoot(fullPath)}:`)
        console.log(referencingFiles.map(fileName => ` - ${fileName}`).join('\n'))
      }

      if (browserTests.length) {
        console.log(`Moving ${browserTests.length} browser test(s):`)
        console.log(browserTests.map(file => ` - ${file.relativePath}`).join('\n'))
      }

      const relativeRoot = parsedPath.dir
      const directories = [...new Set(files.map(file => path.dirname(file)))]
      const isEntryPoint = relativeRoot === appAssetsModulesPath || files.some(file => file.endsWith('ssr-entry.ts'))
      const browserTestDirectory = fullPathFromRoot(`ui/packages/${packageName}/__browser-tests__`)

      function getDestinationPath(relativePath: string) {
        return fullPathFromRoot(
          `ui/packages/${packageName}/${path.relative(relativeRoot, fullPathFromRoot(relativePath))}`,
        )
      }

      function getBrowserTestPath(relativePath: string) {
        const {name, ext} = path.parse(relativePath)
        // Convert name like test-foo.ts to foo.test.ts
        const newFileName = `${name.replace('test-', '')}.test${ext}`
        return fullPathFromRoot(`${browserTestDirectory}/${newFileName}`)
      }

      const actions = [
        ...directories.map(directory => ({
          type: 'runCommand',
          cmd: 'mkdir',
          args: ['-p', getDestinationPath(directory)],
        })),
        ...files.map((file: string) => ({
          type: 'runCommand',
          cmd: 'git',
          args: ['mv', fullPathFromRoot(file), getDestinationPath(file)],
        })),
        {
          // Remove existing SERVICEOWNERS entries
          type: 'replaceInFile',
          path: fullPathFromRoot('SERVICEOWNERS'),
          matcher: new RegExp(
            `(${[...files, ...browserTests.map(test => test.relativePath)].join('|').replace(/\./g, '\\.')}).*\\n`,
            'g',
          ),
          newValue: '',
        },
        // Move related browser tests, if any
        ...(browserTests.length
          ? [
              // Make the __browser-tests__ directory
              {
                type: 'runCommand',
                cmd: 'mkdir',
                args: ['-p', browserTestDirectory],
              },
              // Move each of the test files
              ...browserTests.map(browserTest => ({
                type: 'runCommand',
                cmd: 'git',
                args: ['mv', fullPathFromRoot(browserTest.relativePath), getBrowserTestPath(browserTest.relativePath)],
              })),
              // Update the file references to use the new relative path
              ...browserTests.map(browserTest => ({
                type: 'replaceInFile',
                path: getBrowserTestPath(browserTest.relativePath),
                matcher: new RegExp(`'\\..*${pathWithoutExtension(relativePathFromRoot(fullPath))}'`, 'g'),
                newValue: `'../${parsedPath.name}'`,
              })),
            ]
          : []),
        ...standardPackageActions,
        // Add a record of the migrated file to the eslint plugin, which ensures all imports are updated
        {
          type: 'addLineToFile',
          line: `  'app/assets/modules/${pathWithoutExtension(pathFromAppAssetModules)}': '@github-ui/${packageName}',`,
          path: '../eslint-plugin-github-monorepo/rules/migrated-package-imports.js',
          sectionStart: '  //---- start of migrated files ----',
          sectionEnd: '  //---- end of migrated files ----',
        } satisfies AddLineToFileConfig,

        // Manually update all referencing files. This uses replaceInFile rather than eslint so that it's fast
        ...referencingFiles
          .filter(referencingFile => !browserTests.some(test => test.relativePath === referencingFile)) // Don't update browser tests, which have already been moved
          .map(referencingFile => {
            const fullReferencingPath = fullPathFromRoot(referencingFile)
            let expectedImportPath = pathWithoutExtension(path.relative(path.dirname(fullReferencingPath), fullPath))
            if (!expectedImportPath.startsWith('.')) {
              expectedImportPath = `./${expectedImportPath}`
            }

            return {
              type: 'replaceInFile',
              path: fullReferencingPath,
              matcher: new RegExp(`'${expectedImportPath}'`, 'g'),
              newValue: `'@github-ui/${packageName}'`,
            }
          }),
        ...(isEntryPoint
          ? [
              // For top-level modules, add an entry point and restart js-assets
              commonActions.entry,
              commonActions.restartJsAssets,
            ]
          : []),
        () =>
          `Next steps:

  - Verify all imports and tests migrated correctly:

      npm run nx:run -- --t=lint,tsc,test -p @github-ui/${packageName} @github-ui/app-assets-modules @github-ui/app-components @github-ui/test-js

  - Verify all browser tests pass:

      npm test

  - Verify there are no lingering SERVICEOWNERS entries for the migrated files:

      script/generate-service-files.rb
`,
      ]

      return actions
    },
  })
}
