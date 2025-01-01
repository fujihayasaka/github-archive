// @ts-check
const {Compilation, NormalModule, sources, ExternalModule} = require('webpack')
const {readFileSync} = require('node:fs')
const path = require('node:path')

const WEBPACK_SETUP_MATCHER =
  /var __webpack_module_cache__ = {}(?<setupCode>.*)module.exports = __webpack_exports__\["default"\];/s

/**
 * @type {(compilation: import('webpack').Compilation, modules: Set<import('webpack').NormalModule>, ids?: Set<string>) => Set<string>}
 * getModuleAndDependencyIds is a recursive function that takes a set of modules and returns the module ids for those
 * modules, as well as their dependencies. We want not only the safe modules, but also anything they depend on to
 * ensure it all gets shared between isolated requests.
 */
function getModuleAndDependencyIds(compilation, modules, ids = new Set()) {
  const dependencies = new Set()

  for (const module of modules) {
    const moduleId = compilation.chunkGraph.getModuleId(module)
    if (!moduleId || ids.has(moduleId.toString()) || !(module instanceof NormalModule)) continue

    ids.add(moduleId.toString())

    for (const dependency of module.dependencies) {
      const dependencyModule = compilation.moduleGraph.getModule(dependency)
      if (dependencyModule) {
        dependencies.add(dependencyModule)
      }
    }
  }

  if (dependencies.size) {
    getModuleAndDependencyIds(compilation, dependencies, ids)
  }

  return ids
}

/**
 * @type {import('webpack').WebpackPluginInstance}
 */
class AlloySelectiveIsolationPlugin {
  /**
   * @constructor
   * @param {{entryNames: string[], trustedModules: string[]}} options
   */
  constructor({entryNames, trustedModules}) {
    this.entryNames = entryNames
    this.trustedModules = trustedModules
  }

  /**
   * @type {import('webpack').WebpackPluginInstance['apply']}
   */
  apply(compiler) {
    compiler.hooks.thisCompilation.tap('AlloySelectiveIsolation', compilation => {
      compilation.hooks.processAssets.tap(
        {
          name: 'AlloySelectiveIsolation',
          stage: Compilation.PROCESS_ASSETS_STAGE_OPTIMIZE,
        },
        () => {
          const chunks = [...compilation.chunks]

          for (const entry of compilation.entries.keys()) {
            const assets = compilation.getAssets()
            const asset = assets.find(a => a.name.startsWith(entry))
            const chunk = chunks.find(c => c.name === entry)

            if (!asset || !chunk) return

            const targetModules = new Set()
            for (const module of compilation.chunkGraph.getChunkModulesIterable(chunk)) {
              // ExternalModules use node require, which has it's own cache
              if (module instanceof ExternalModule) continue

              // runtime uses a unique module type, but we don't want it in the trusted modules list
              if (module.type === 'runtime') continue

              // Any non-normal module is unexpected, e.g. a ConcatenatedModule would cause problems
              // Throw if we find one so we can investigate
              if (!(module instanceof NormalModule)) {
                throw new Error(`Unexpected Webpack module type: ${module.constructor.name}`)
              }

              if (module.resource && this.trustedModules.some(dep => module.resource.includes(dep))) {
                targetModules.add(module)
              }
            }
            const safeModuleIds = getModuleAndDependencyIds(compilation, targetModules)

            const newSource = this.isolateSource(asset, [...safeModuleIds])
            if (newSource) compilation.updateAsset(asset.name, newSource)
          }
        },
      )
    })
  }

  /**
   * @type {(manifestPath: import('webpack').Asset, safeModuleIds: string[]) => import('webpack').sources.ReplaceSource | undefined}
   */
  isolateSource(asset, safeModuleIds) {
    const source = String(asset.source.source())

    // There can be multiple setup blocks in the source because some of our deps are also built with webpack
    const lastSetupBlockIndex = source.lastIndexOf('var __webpack_module_cache__ = {}')
    const lastSetupBlock = source.slice(lastSetupBlockIndex)

    const webpackSetupCodeMatch = lastSetupBlock.match(WEBPACK_SETUP_MATCHER)
    const webpackSetupCode = webpackSetupCodeMatch?.groups?.setupCode

    if (!webpackSetupCodeMatch || !webpackSetupCode) {
      throw new Error('Unable to find webpack setup code in asset source')
    }

    const webpackSetupCodeWithExport = webpackSetupCodeMatch[0]

    const newSource = new sources.ReplaceSource(asset.source, asset.name)
    const start = source.indexOf(webpackSetupCodeWithExport)
    const end = start + webpackSetupCodeWithExport.length
    const injectedSource = readFileSync(path.join(__dirname, 'alloy-selective-isolation-injected.js'), 'utf8')

    /**
     * We have eliminated the top-level __webpack_module_cache__ so that we can dynamically choose between
     * the trusted and untrusted caches. Update the `__webpack_require__` function to use the correct cache
     * based on whether the required module is trusted.
     */
    const webpackSetup = webpackSetupCode.replace(
      /(function __webpack_require__\(.*)/,
      `$1
/* injected */ const isTrusted = safeModuleIds.has(moduleId.toString())
/* injected */ const __webpack_module_cache__ = isTrusted ? trustedModuleCache : untrustedModuleCache`,
    )

    const isolatedSource = injectedSource
      .replace('/*# safeModuleIds #*/', JSON.stringify(safeModuleIds))
      .replace('/*# entryNames #*/', JSON.stringify(this.entryNames))
      .replace('/*# webpackSetup #*/', webpackSetup)

    newSource.replace(start, end, isolatedSource)
    return newSource
  }
}

module.exports = AlloySelectiveIsolationPlugin
