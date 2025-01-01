import {fileUrl, newFileUrl, overviewUrl} from '../urls'

describe('overview', () => {
  const args = {owner: 'owner', repo: 'repo', pullNumber: '1'}

  test('plain', () => {
    const location = {search: ''}
    expect(overviewUrl({...args, location})).toBe('/owner/repo/pull/1/edit')
  })

  test('with query params', () => {
    const location = {search: '?stuff=things'}
    expect(overviewUrl({...args, location})).toBe('/owner/repo/pull/1/edit?stuff=things')
  })
})

describe('fileUrl', () => {
  const args = {owner: 'owner', repo: 'repo', pullNumber: '1', path: 'README.md'}

  test('plain', () => {
    const location = {search: ''}
    expect(fileUrl({...args, location})).toBe('/owner/repo/pull/1/edit/file/README.md')
  })

  test('with query params', () => {
    const location = {search: '?stuff=things'}
    expect(fileUrl({...args, location})).toBe('/owner/repo/pull/1/edit/file/README.md?stuff=things')
  })

  test('with file path that has characters that should be escaped', () => {
    const location = {search: ''}
    expect(fileUrl({...args, location, owner: '#owner', repo: '#repo', path: '#README.md'})).toBe(
      '/%23owner/%23repo/pull/1/edit/file/%23README.md',
    )
  })
})

describe('newFileUrl', () => {
  const args = {owner: 'owner', repo: 'repo', pullNumber: '1'}

  test('plain', () => {
    const location = {search: ''}
    expect(newFileUrl({...args, location})).toBe('/owner/repo/pull/1/edit/new')
  })

  test('with query params', () => {
    const location = {search: '?stuff=things'}
    expect(newFileUrl({...args, location})).toBe('/owner/repo/pull/1/edit/new?stuff=things')
  })
})
