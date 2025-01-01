import {injectAlloyEntryImports} from '../alloy-entry'
import {readFileSync} from 'node:fs'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'
import {getSSREntryPoints} from '@github-ui/client-build-tools/entry-points'

const pathToEntry = fullPathFromRoot('ui/packages/alloy-entry/alloy-entry.ts')
const ssrEntries = getSSREntryPoints()

describe('alloy entry', () => {
  it('should inject a dynamic import for each ssr entry', () => {
    const source = readFileSync(pathToEntry, 'utf8')
    const result = injectAlloyEntryImports(source, pathToEntry, ssrEntries)

    // example from ui/packages
    expect(result).toContain(`'react-sandbox': () => require('../react-sandbox/ssr-entry.ts'),`)
  })

  it('should allow the import type to be overridden', () => {
    const source = readFileSync(pathToEntry, 'utf8')
    const result = injectAlloyEntryImports(source, pathToEntry, ssrEntries, 'import')

    // example from ui/packages
    expect(result).toContain(`'react-sandbox': () => import('../react-sandbox/ssr-entry.ts'),`)
  })

  it('should throw if the placeholder is not found', () => {
    const source = `{
      /* incorrect placeholder here */
    }`
    expect(() => injectAlloyEntryImports(source, pathToEntry, ssrEntries)).toThrow(
      `Alloy entry plugin: no placeholder found for file ${pathToEntry}`,
    )
  })

  it('should return undefined if the path is not to element-registry.ts', () => {
    expect(injectAlloyEntryImports('source', 'path/to/other/file.ts', ssrEntries)).toBeUndefined()
  })
})
