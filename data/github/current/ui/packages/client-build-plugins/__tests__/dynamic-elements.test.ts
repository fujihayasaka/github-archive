import {injectDynamicElementImports} from '../dynamic-elements'
import {readFileSync} from 'node:fs'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'

const pathToRegistry = fullPathFromRoot('app/assets/modules/element-registry.ts')

describe('dynamic elements', () => {
  it('should inject a dynamic import for each element', () => {
    const source = readFileSync(pathToRegistry, 'utf8')
    const result = injectDynamicElementImports(source, pathToRegistry)

    // example from app/components
    expect(result).toContain(
      `'navigation-list': () => import('../../components/navigation/navigation-list-element.ts'),`,
    )

    // example from ui/packages
    expect(result).toContain(
      `'react-partial-anchor': () => import('../../../ui/packages/react-partial-anchor-element/element-entry.ts'),`,
    )
  })

  it('should throw if the placeholder is not found', () => {
    const source = `lazyDefine({
      /* incorrect placeholder here */
    })`
    expect(() => injectDynamicElementImports(source, pathToRegistry)).toThrow(
      `Dynamic elements loader: no match found for file ${pathToRegistry}`,
    )
  })

  it('should return undefined if the path is not to element-registry.ts', () => {
    expect(injectDynamicElementImports('source', 'path/to/other/file.ts')).toBeUndefined()
  })
})
