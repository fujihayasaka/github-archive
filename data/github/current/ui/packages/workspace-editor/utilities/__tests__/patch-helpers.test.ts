import {formatPatches} from '../patch-helpers'

describe('formatPatch', () => {
  test('empty list', () => {
    const newPatches = formatPatches([])
    expect(newPatches).toEqual({})
  })

  test('one patch', () => {
    const newPatches = formatPatches([
      {
        oldFilePath: 'README.md',
        newFilePath: 'README.md',
        oldContents: 'Hello world\n',
        newContents: 'Later computer\n',
      },
    ])
    expect(newPatches).toEqual({
      'README.md': {
        hunks: [
          {
            linedelimiters: ['\n', '\n'],
            lines: ['-Hello world', '+Later computer'],
            newLines: 1,
            newStart: 1,
            oldLines: 1,
            oldStart: 1,
          },
        ],
        newFileName: 'README.md',
        newHeader: undefined,
        oldFileName: 'README.md',
        oldHeader: undefined,
      },
    })
  })

  test('multiple patches', () => {
    const newPatches = formatPatches([
      {
        oldFilePath: 'README.md',
        newFilePath: 'README.md',
        oldContents: 'Hello world\n',
        newContents: 'Later computer\n',
      },
      {
        oldFilePath: 'Another.md',
        newFilePath: 'Another.md',
        oldContents: 'Hi\n',
        newContents: 'Bye\n',
      },
    ])
    expect(newPatches).toEqual({
      'README.md': {
        hunks: [
          {
            linedelimiters: ['\n', '\n'],
            lines: ['-Hello world', '+Later computer'],
            newLines: 1,
            newStart: 1,
            oldLines: 1,
            oldStart: 1,
          },
        ],
        newFileName: 'README.md',
        newHeader: undefined,
        oldFileName: 'README.md',
        oldHeader: undefined,
      },
      'Another.md': {
        hunks: [
          {
            linedelimiters: ['\n', '\n'],
            lines: ['-Hi', '+Bye'],
            newLines: 1,
            newStart: 1,
            oldLines: 1,
            oldStart: 1,
          },
        ],
        newFileName: 'Another.md',
        newHeader: undefined,
        oldFileName: 'Another.md',
        oldHeader: undefined,
      },
    })
  })

  test('no combining, last in wins', () => {
    const newPatches = formatPatches([
      {
        oldFilePath: 'README.md',
        newFilePath: 'README.md',
        oldContents: 'Hello world\n',
        newContents: 'Later computer\n',
      },
      {
        oldFilePath: 'README.md',
        newFilePath: 'README.md',
        oldContents: 'Hi\n',
        newContents: 'Bye\n',
      },
    ])
    expect(newPatches).toEqual({
      'README.md': {
        hunks: [
          {
            linedelimiters: ['\n', '\n'],
            lines: ['-Hi', '+Bye'],
            newLines: 1,
            newStart: 1,
            oldLines: 1,
            oldStart: 1,
          },
        ],
        newFileName: 'README.md',
        newHeader: undefined,
        oldFileName: 'README.md',
        oldHeader: undefined,
      },
    })
  })
})
