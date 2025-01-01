import {trimFileName} from '../utils/trim-file-name'

describe('trimFileName', () => {
  it('should return undefined for a root repo path', () => {
    expect(trimFileName('/home/runner/work/sweagentd/sweagentd/')).toBe(undefined)
  })

  it('should return just the file name for a file at the repo root', () => {
    expect(trimFileName('/home/runner/work/sweagentd/sweagentd/package.json')).toBe('package.json')
  })

  it('should return the relative path for a file in a subdirectory', () => {
    expect(trimFileName('/home/runner/work/sweagentd/sweagentd/src/app/App.tsx')).toBe('src/app/App.tsx')
  })
})
