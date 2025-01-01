import {fullPathFromRoot, globFromRoot} from '@github-ui/client-build-tools/path-utils'
// eslint-disable-next-line import/no-nodejs-modules
import path from 'path'
import {Legacy} from '@eslint/eslintrc'

type ConfigTree = {[key: string]: ConfigNode}
interface ESLintConfig {
  root?: boolean
  extends?: string | string[]
  rules: {[key: string]: unknown}
}

const configArrayFactory = new Legacy.ConfigArrayFactory()
const extendCache = new Map<string, ESLintConfig>()

class ConfigNode {
  path: string
  dir: string
  parent?: ConfigNode
  ancestorsCache?: ConfigNode[]
  extensionRulesCache?: {[key: string]: unknown}
  config: ESLintConfig
  extendedModules = new Set<ESLintConfig>()

  constructor(filePath: string, dir: string) {
    this.path = filePath
    this.dir = dir
    // eslintrc package doesn't handle mjs files
    // eslint-disable-next-line import/no-dynamic-require, @typescript-eslint/no-require-imports
    this.config = filePath.endsWith('.mjs') ? require(filePath) : Legacy.loadConfigFile(filePath)
    this.#loadExtends()
  }

  get rules() {
    return this.config.rules
  }

  get extensionRules(): {[key: string]: unknown} {
    if (this.extensionRulesCache) return this.extensionRulesCache

    let extensionRules: {[key: string]: unknown} = {}

    for (const module of this.extendedModules) {
      extensionRules = {
        ...extensionRules,
        ...module.rules,
      }
    }

    this.extensionRulesCache = extensionRules

    return this.extensionRulesCache
  }

  ancestors(): ConfigNode[] {
    // root configs don't inherit from an upper-level config
    if (this.config.root || !this.parent) return []
    if (this.ancestorsCache) return this.ancestorsCache

    let ancestors: ConfigNode[] = []

    if (this.parent) {
      ancestors = [this.parent, ...this.parent.ancestors()]
    }

    this.ancestorsCache = ancestors
    return this.ancestorsCache
  }

  #loadExtends() {
    if (!this.config.extends) return

    const names = Array.isArray(this.config.extends) ? this.config.extends : [this.config.extends]

    for (const extendName of names) {
      const module = this.#loadExtend(extendName)
      this.extendedModules.add(module)
      extendCache.set(extendName, module)
    }
  }

  #loadExtend(extendName: string): ESLintConfig {
    if (extendCache.has(extendName)) {
      return extendCache.get(extendName)!
    }

    if (extendName.startsWith('eslint:')) {
      return this.#loadExtendedBuiltInConfig(extendName)
    }

    if (extendName.startsWith('plugin:')) {
      return this.#loadExtendedPluginConfig(extendName)
    }

    return this.#loadExtendedShareableConfig(extendName)
  }

  // eslint plugins don't follow the convention.
  #loadExtendedBuiltInConfig(extendName: string): ESLintConfig {
    const configName = extendName.replace('eslint:', '')
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    return this.#loadWithFactory(require('@eslint/js').configs[configName], {
      packageName: '@eslint/js',
    })
  }

  // plugins are either `eslint-plugin-pluginName` or `@namespace/eslint-plugin` or `@namespace/eslint-plugin-pluginName`.
  #loadExtendedPluginConfig(extendName: string): ESLintConfig {
    const slashIndex = extendName.lastIndexOf('/')
    const packageName = extendName.slice('plugin:'.length, slashIndex)
    const configName = extendName.slice(slashIndex + 1)

    const packageInfo = getPackageInfo(packageName)
    // eslint-disable-next-line import/no-dynamic-require, @typescript-eslint/no-require-imports
    return this.#loadWithFactory(require(packageInfo.pluginPackageName).configs[configName], {
      packageName: packageInfo.pluginPackageName,
    })
  }

  #loadExtendedShareableConfig(extendName: string): ESLintConfig {
    // relative paths
    if (extendName.startsWith('.')) {
      const fullPath = path.resolve(extendName)
      return this.#loadWithFactory(Legacy.loadConfigFile(fullPath), {
        requirePath: fullPath,
      })
    }

    const packageInfo = getPackageInfo(extendName)
    // eslint-disable-next-line import/no-dynamic-require, @typescript-eslint/no-require-imports
    return this.#loadWithFactory(require(packageInfo.configPackageName), {
      packageName: packageInfo.configPackageName,
    })
  }

  // The factory will load all plugins and extensions directly into the config. We do this for plugins since
  // we don't care if the rule came from another plugin, we only care if the current plugin has a rule.
  #loadWithFactory(config: ESLintConfig, opts: {requirePath?: string; packageName?: string} = {}): ESLintConfig {
    let filePath = ''
    if (opts.requirePath) {
      filePath = path.resolve(opts.requirePath)
    } else if (opts.packageName) {
      filePath = require.resolve(opts.packageName)
    }

    return configArrayFactory
      .create(config, {
        basePath: path.resolve(),
        filePath,
        name: opts.packageName ? opts.packageName : path.basename(filePath),
      })
      .extractConfig()
  }
}

function normalizeName(name: string, type: 'plugin' | 'config') {
  if (name.startsWith(`eslint-${type}`)) {
    return name
  } else if (name === '') {
    return `eslint-${type}`
  }

  return `eslint-${type}-${name}`
}

function getPackageInfo(name: string) {
  if (!name.startsWith('@')) {
    return {
      namespace: '',
      packageName: name,
      pluginPackageName: normalizeName(name, 'plugin'),
      configPackageName: normalizeName(name, 'config'),
    }
  }

  const packageSplit = name.split('/')
  const packageName = packageSplit[1] || ''
  const namespace = packageSplit[0]
  return {
    namespace,
    packageName,
    pluginPackageName: `${namespace}/${normalizeName(packageName, 'plugin')}`,
    configPackageName: `${namespace}/${normalizeName(packageName, 'config')}`,
  }
}

function findClosestParentConfig(node: ConfigNode, eslintConfigs: ConfigTree): ConfigNode | undefined {
  // start with a dir above
  let currentDir = path.dirname(node.dir)

  // While not at the root
  while (currentDir !== path.dirname(currentDir)) {
    const potentialParent = eslintConfigs[currentDir]
    if (potentialParent) return potentialParent

    currentDir = path.dirname(currentDir) // Move one directory up
  }

  // check root eslint config
  const potentialParent = eslintConfigs[currentDir]
  if (potentialParent) return potentialParent

  return // If no parent is found
}

// Function to build the ESLint config tree
export function buildESLintConfigTree(): ConfigTree {
  const initialValue: {[key: string]: ConfigNode} = {}
  const eslintConfigs: ConfigTree = [
    fullPathFromRoot('.eslintrc.js'),
    ...globFromRoot('{app,test,ui}/**/{.eslintrc,.eslintrc.js,.eslintrc.cjs,.eslintrc.mjs}', {
      ignore: '**/node_modules/**',
    }),
  ].reduce((acc, fullPath) => {
    const dir = path.dirname(fullPath)
    acc[dir] = new ConfigNode(fullPath, dir)
    return acc
  }, initialValue)

  // For each config file, find the closest parent and add to the tree
  for (const node of Object.values(eslintConfigs)) {
    const possibleParent = findClosestParentConfig(node, eslintConfigs)
    if (possibleParent?.path !== node.path) node.parent = possibleParent
  }

  return eslintConfigs
}
