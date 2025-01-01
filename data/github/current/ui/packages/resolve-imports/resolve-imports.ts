import {parseFile} from '@swc/core'
import path from 'path'
import fs from 'node:fs'
import {relativePathFromRoot} from '@github-ui/client-build-tools/path-utils'

/**
 * Shared cache for all dependencies. This makes it possible to short-circuit
 * if a dependency requires a file which has already been traversed
 */
const dependencyCache = new Map<string, Dependency>()

/**
 * Vite will reload the server when config files change, but it does so in the same
 * node process. We need to detect these restarts and abort our file watchers from the
 * previous server run
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const watchAbortControllers: AbortController[] = ((globalThis as any).watchAbortControllers ||= [])
for (const controller of watchAbortControllers) {
  controller.abort()
}
watchAbortControllers.length = 0

/**
 * Many of our imports do not include the file extension, so we need to try
 * multiple extensions to find the correct file
 *
 * We use different extension ordering for PascalCase and kebab-case imports, as .tsx files are generally PascalCase
 */
const availableExtensions = ['.ts', '.tsx', '/index.ts', '/index.tsx', '.js']
const availablePascalExtensions = ['.tsx', '.ts', '/index.tsx', '/index.ts']
function getPathWithExtension(importPath: string) {
  const {ext: existingExtension, name} = path.parse(importPath)
  if (existingExtension) {
    return importPath
  }

  const isPascalCase = name[0]?.toUpperCase() === name[0]
  const extensions = isPascalCase ? availablePascalExtensions : availableExtensions

  for (const ext of extensions) {
    try {
      const fullPath = importPath + ext
      // fs.accessSync wil throw an error if the file does not exist. This is faster than any fs.* equivalent
      fs.accessSync(fullPath)
      return fullPath
    } catch {
      // Ignore the error and try the next extension
    }
  }

  console.error('❌ Could not resolve import', importPath)
}

/**
 * The Dependency class is responsible for parsing it's own source code, then
 * registering any dependencies it finds. It can then recursively find all child
 * dependencies.
 *
 * It also watches it's own file for changes, invalidating it's cached dependency list
 * when the source changes
 */
class Dependency {
  private directDependenciesPromise: Promise<Set<Dependency>> | null = null
  readonly path: string
  private directNpmDependencies = new Set<string>()

  constructor(fullPath: string) {
    this.path = fullPath

    // Watch the file for changes
    const controller = new AbortController()
    watchAbortControllers.push(controller)
    fs.watch(fullPath, {signal: controller.signal}, () => {
      // remove the cached dependencies, forcing a re-evaluation next time they are requested
      this.directDependenciesPromise = null
    })
  }

  async parseDirectDependencies() {
    // Reset the direct npm dependencies each time we parse the file
    this.directNpmDependencies.clear()

    const ast = await parseFile(this.path, {
      syntax: 'typescript',
      tsx: this.path.endsWith('.tsx'),
      decorators: true,
    })

    const dependencies = new Set<Dependency>()

    for (const item of ast.body) {
      if (
        item.type !== 'ImportDeclaration' &&
        item.type !== 'ExportAllDeclaration' &&
        item.type !== 'ExportNamedDeclaration' &&
        item.type !== 'ExportDefaultDeclaration'
      ) {
        continue
      }

      if (!('source' in item) || !item.source) {
        continue
      }

      const source = item.source.value
      const sourceExt = path.extname(source)

      if (sourceExt) {
        if (sourceExt !== '.ts' && sourceExt !== '.tsx' && sourceExt !== '.js' && sourceExt !== '.css') {
          continue
        }
      }

      if (source.startsWith('.')) {
        // Relative imports are considered direct dependencies and should be traversed further
        try {
          const importPath = await getPathWithExtension(path.resolve(path.dirname(this.path), source))

          if (!importPath || importPath.endsWith('.server.ts')) {
            continue
          }

          dependencies.add(getOrCreateDependency(importPath))
        } catch (e) {
          console.error('failed to resolve', source)
          console.error(e)
        }
      } else {
        // non-relative imports are generally npm dependencies
        const partsToUse = source.startsWith('@') ? 2 : 1
        const packageName = source.split('/').slice(0, partsToUse).join('/')

        this.directNpmDependencies.add(packageName)
      }
    }

    return dependencies
  }

  get hasChanged() {
    return !this.directDependenciesPromise
  }

  private async getDirectDependencies() {
    // Don't try to parse or traverse CSS files
    if (this.path.endsWith('.css')) {
      return (this.directDependenciesPromise ||= Promise.resolve(new Set<Dependency>()))
    }

    return (this.directDependenciesPromise ||= this.parseDirectDependencies())
  }

  async getAllDependencies(dependencies = new Set<Dependency>()): Promise<Set<Dependency>> {
    if (dependencies.has(this)) {
      return dependencies
    }

    dependencies.add(this)

    try {
      const directDependencies = [...(await this.getDirectDependencies())]
      await Promise.all(directDependencies.map(dep => dep.getAllDependencies(dependencies)))
    } catch (e) {
      console.error('failed to get all dependencies for', this.path)
      console.error(e)
    }

    return dependencies
  }

  getNpmDependencies() {
    return [...this.directNpmDependencies]
  }
}

function getOrCreateDependency(fullPath: string) {
  const dependency = dependencyCache.get(fullPath) || new Dependency(fullPath)
  dependencyCache.set(fullPath, dependency)
  return dependency
}

/**
 * Given an entry file, resolves all relatively imported files and npm dependencies by traversing the dependency graph
 */
export async function resolveImports(entryFile: string) {
  const dependency = getOrCreateDependency(entryFile)
  const dependencies = [...(await dependency.getAllDependencies())]

  return {
    files: dependencies.map(dep => relativePathFromRoot(dep.path)).sort(),
    dependencies: [...new Set(dependencies.map(dep => dep.getNpmDependencies()).flat())].sort(),
  }
}

/**
 * This helper provides a quick way for external code to see if it needs to call resolveImports again
 * If no dependencies have changed, they can re-use previous results
 */
export function haveAnyDependenciesChanged() {
  for (const [, dependency] of dependencyCache) {
    if (dependency.hasChanged) {
      return true
    }
  }
  return false
}

/**
 * This helper is used to abort all file watchers when tests are done running
 */
export function __abortWatchers() {
  for (const controller of watchAbortControllers) {
    controller.abort()
  }
}
