// @ts-check
import path from 'node:path'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'

/**
 * This custom webpack plugin is responsible for setting up dynamic imports for alloy/ssr entry points.
 * Any package within ui/packages with an `ssr-entry.ts` should get automatically included in the alloy bundle.
 *
 * Example Input:
 *
 * /* Insert dynamic ssr-entry.ts imports here *\/
 *
 * Example Output (replaces the comment above):
 *
 * import './ui/packages/notification-settings/alloy-import'
 * ....
 */

const importPlaceholder = '/* Insert dynamic ssr-entry.ts imports here */'

/**
 * @param {string} source The source code of the file being transformed
 * @param {string} filePath The path to the file being transformed
 * @param {Record<string, string>} ssrEntries Map of package names to ssr entry files
 * @param {'import'|'require'} importType The type of import to use
 */
export function injectAlloyEntryImports(source, filePath, ssrEntries, importType = 'require') {
  if (!filePath.endsWith('ui/packages/alloy-entry/alloy-entry.ts') && !filePath.endsWith('fixtures/alloy-entry.js')) {
    return
  }

  if (!source.includes(importPlaceholder)) {
    throw new Error(`Alloy entry plugin: no placeholder found for file ${filePath}`)
  }

  const alloyEntryDir = path.dirname(filePath)

  // Look for `ssr-entry.ts` files in both `ui/packages` and `app/assets/modules`
  const dynamicImports = Object.entries(ssrEntries).map(([packageName, file]) => {
    // use a relative path so that sourcemaps are the same in all build environments
    let relativePath = path.relative(alloyEntryDir, fullPathFromRoot(file))
    if (!relativePath.startsWith('.')) {
      relativePath = `./${relativePath}`
    }
    return `'${packageName}': () => ${importType}('${relativePath}')`
  })

  const output = dynamicImports.join(',\n')
  return source.replace(importPlaceholder, output)
}
