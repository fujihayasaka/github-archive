import {findServiceowners} from '../find-serviceowners.js'
import {join} from 'node:path'

const matchAll = /./
const FIXTURES_PATH = join(__dirname, 'fixtures', 'fake-so')

describe('findServiceowners', () => {
  it('matches an exact file name', () => {
    expect(findServiceowners('my/file.js', matchAll, FIXTURES_PATH)).toEqual(['file_owner'])
  })

  it('matches a directory', () => {
    expect(findServiceowners('my/dir/deep/file.js', matchAll, FIXTURES_PATH)).toEqual(['dir_owner'])
  })

  it('matches a glob', () => {
    expect(findServiceowners('with/some/deep/globs/thing.js', matchAll, FIXTURES_PATH)).toEqual(['with_globs'])
  })

  it('matches multiple owners', () => {
    expect(findServiceowners('multi/owner', matchAll, FIXTURES_PATH)).toEqual(['first_owner', 'second_owner'])
  })

  it('matches a real owner', () => {
    expect(findServiceowners('ui/packages/find-serviceowners/package.json', matchAll)).toEqual(['frontend_systems'])
  })

  it('returns null if no owner is found', () => {
    expect(findServiceowners('not/real', matchAll, FIXTURES_PATH)).toEqual(null)
  })

  it('filters by provided matcher regex', () => {
    const myFileMatcher = /my\/file/
    expect(findServiceowners('my/file.js', myFileMatcher, FIXTURES_PATH)).toEqual(['file_owner'])
    // no match because the matcher for the dir does not match the provided matcher regex
    expect(findServiceowners('my/dir/deep/file.js', myFileMatcher, FIXTURES_PATH)).toEqual(null)
  })
})
