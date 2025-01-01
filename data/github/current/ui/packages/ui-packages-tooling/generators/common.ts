import {paramCase as kebabCase} from 'change-case'
import type {AddLineToFileConfig} from './actions/add-line-to-file.ts'
import type {RunCommandConfig} from './actions/run-command.ts'
import {listMatchingServices, listMatchingTeams} from './prompts/available-services.ts'
import {accessSync} from 'node:fs'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'
import {listMatchingPackages} from './prompts/available-packages.ts'

export const requiredPrompt = (value: string) => !!value

export function templatePath(path: string) {
  return `./templates/${path}`
}

export function packagePath(path: string) {
  return `../{{packageName}}/${path}`
}

export const commonPrompts = {
  packageName: {
    type: 'input',
    name: 'packageName',
    message: 'Package name:',
    filter: kebabCase,
    validate: (input: string) => {
      if (!input) {
        return false
      }

      try {
        // If there is already an existing package.json, the package already exists
        accessSync(fullPathFromRoot(`ui/packages/${input}/package.json`))
        return `Package ${input} already exists. Please choose a different package name.`
      } catch {
        // Unable to find package.json, so no package exists and the name can be used
        return true
      }
    },
  },
  description: {
    type: 'input',
    name: 'packageDescription',
    message: 'Brief description:',
    validate: requiredPrompt,
  },
  service: {
    type: 'autocomplete',
    name: 'service',
    message: 'Service name for SERVICEOWNERS:',
    source: (_: unknown, input: string) => listMatchingServices(input),
    validate: requiredPrompt,
  },
  team: {
    type: 'autocomplete',
    name: 'team',
    message: 'Service owner team name:',
    source: (_: unknown, input: string) => listMatchingTeams(input),
    validate: requiredPrompt,
  },
  package: {
    type: 'autocomplete',
    name: 'package',
    message: 'Select a package:',
    source: (_: unknown, input: string) => listMatchingPackages(input),
    validate: requiredPrompt,
  },
  ssr: {
    type: 'confirm',
    name: 'enableSSR',
    default: true,
  },
}

export const commonActions = {
  packageJson: {
    type: 'add',
    path: packagePath('package.json'),
    templateFile: templatePath('package.json.hbs'),
  },
  entry: {
    type: 'add',
    path: packagePath('entry.ts'),
    templateFile: templatePath('entry.ts.hbs'),
  },
  ssrEntry: {
    type: 'add',
    path: packagePath('ssr-entry.ts'),
    templateFile: templatePath('ssr-entry.ts.hbs'),
  },
  serviceowners: {
    type: 'addLineToFile',
    line: 'ui/packages/{{packageName}}/ :{{service}}',
    path: '../../../SERVICEOWNERS',
    sectionStart: '# UI packages',
    sectionEnd: '# End of UI packages',
  } satisfies AddLineToFileConfig,
  gitAddPackageJson: {
    type: 'runCommand',
    cmd: 'git',
    args: ['add', 'ui/packages/{{packageName}}/package.json'],
  } satisfies RunCommandConfig,
  gitUnstagePackageJson: {
    type: 'runCommand',
    cmd: 'git',
    args: ['restore', '--staged', 'ui/packages/{{packageName}}/package.json'],
  } satisfies RunCommandConfig,
  generateServiceFiles: {
    type: 'runCommand',
    cmd: 'script/generate-service-files.rb',
    ignoreFailure: true,
  } satisfies RunCommandConfig,
  mainFile: {
    type: 'add',
    path: packagePath('{{packageName}}.ts'),
    templateFile: templatePath('main.ts.hbs'),
  },
  npmInstall: {
    type: 'runCommand',
    cmd: 'npm',
    args: ['install', '--ignore-scripts'],
  } satisfies RunCommandConfig,
  restartJsAssets: {
    type: 'runCommand',
    cmd: 'overmind',
    args: ['restart', 'js-assets'],
    ignoreFailure: true,
  } satisfies RunCommandConfig,
  restartAlloyAssets: {
    type: 'runCommand',
    cmd: 'overmind',
    args: ['restart', 'alloy-assets'],
    ignoreFailure: true,
  } satisfies RunCommandConfig,
  baseTsconfig: {
    type: 'add',
    path: packagePath('tsconfig.json'),
    templateFile: templatePath('tsconfig.json.hbs'),
  },
  jestConfig: {
    type: 'add',
    path: packagePath('jest.config.js'),
    templateFile: templatePath('jest.config.js.hbs'),
  },
}

export const standardPackageActions = [
  commonActions.packageJson,
  commonActions.baseTsconfig,
  commonActions.jestConfig,
  commonActions.serviceowners,
  commonActions.gitAddPackageJson,
  commonActions.generateServiceFiles,
  commonActions.gitUnstagePackageJson,
  commonActions.npmInstall,
]

export const standardScripts = {
  lint: 'eslint . --cache',
  stylelint: 'stylelint --aei --rd "**/*.css"',
  test: 'jest',
  tsc: 'tsc',
}

export function getScriptsJsonContent(scripts: Record<string, string>) {
  const orderedScripts = Object.keys(scripts)
    .sort()
    .reduce(
      (obj, key) => {
        obj[key] = scripts[key]!
        return obj
      },
      {} as Record<string, string>,
    )

  return JSON.stringify(orderedScripts, null, 4).slice(1, -1).trim()
}

export const standardDevDependencies = {
  '@github-ui/eslintrc': '*',
  '@github-ui/jest': '*',
}

export function getDependencyJsonContent(deps: Record<string, string>) {
  const orderedDeps = Object.keys(deps)
    .sort()
    .reduce(
      (obj, key) => {
        obj[key] = deps[key]!
        return obj
      },
      {} as Record<string, string>,
    )

  return JSON.stringify(orderedDeps, null, 4).slice(1, -1).trim()
}
