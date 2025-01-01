// @ts-check
import path from 'node:path'
import {getDynamicElementEntryPoints} from '@github-ui/client-build-tools/entry-points'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'

/**
 * This plugin is responsible for setting up dynamic imports for all custom elements located in
 * app/components or ui/packages. We expect this plugin to only be run in a single place (element-registry.ts),
 * and for the `lazyDefine` function to be present in the file before this import statement
 *
 *
 * Example Input
 *
 * lazyDefine({
 *  /*# Insert dynamic *-element.ts entries here #*\/
 * })
 *
 *
 * Example Output (replaces the import above)
 *
 * lazyDefine({
 *   'auto-playable', () => import('../../components/accessibility/auto-playable-element.ts')),
 *   'launch-code', () => import('../../components/account_verifications/launch-code-element.ts')),
 *   'action-list', () => import('../../../ui/packages/experimental-action-list-element/element-entry.ts')),
 * })
 * ....
 */

const placeholderComment = '/*# Insert dynamic *-element.ts entries here #*/'

/**
 * @param {string} source The source code of the file being transformed
 * @param {string} filePath The path to the file being transformed
 */
export function injectDynamicElementImports(source, filePath) {
  if (!filePath.endsWith('element-registry.ts')) {
    return
  }

  const match = source.includes(placeholderComment)

  if (!match) {
    throw new Error(`Dynamic elements loader: no match found for file ${filePath}`)
  }

  const dynamicElementEntries = getDynamicElementEntryPoints()
  const registryDir = path.dirname(filePath)

  const output = Object.entries(dynamicElementEntries)
    .map(([elementName, elementPathFromRoot]) => {
      return `'${elementName}': () => import('${path.relative(registryDir, fullPathFromRoot(elementPathFromRoot))}'),`
    })
    .join('\n  ')

  return source.replace(placeholderComment, output)
}
