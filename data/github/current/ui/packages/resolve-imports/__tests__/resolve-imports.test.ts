/** @jest-environment node */
import {resolveImports, __abortWatchers} from '../resolve-imports'
import path from 'node:path'
import {relativePathFromRoot} from '@github-ui/client-build-tools/path-utils'

function getFixturePath(name: string) {
  const extension = name.includes('.') ? '' : '.ts'
  return path.join(__dirname, `fixtures/${name}${extension}`)
}

function getExpectedImportPaths(names: string[]) {
  return names.map(name => relativePathFromRoot(getFixturePath(name))).sort()
}

describe('resolve imports', () => {
  afterAll(__abortWatchers)

  it('should resolve imports and npm dependencies', async () => {
    expect(await resolveImports(getFixturePath('entry-1'))).toEqual({
      files: getExpectedImportPaths(['entry-1', 'dep-1', 'dep-2', 'nested-dep', 'deep-dep.tsx']),
      dependencies: ['@github-ui/resolve-imports'],
    })

    expect(await resolveImports(getFixturePath('entry-2'))).toEqual({
      files: getExpectedImportPaths(['entry-2', 'dep-2', 'nested-dep', 'deep-dep.tsx']),
      dependencies: [],
    })
  })
})
