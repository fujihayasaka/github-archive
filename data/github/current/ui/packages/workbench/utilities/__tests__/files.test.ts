import {buildFileTree} from '../files'

describe('File tree builder', () => {
  it('all root', () => {
    const files = ['index.html', 'package.json']
    const actual = buildFileTree(files)

    expect({
      'index.html': null,
      'package.json': null,
    }).toStrictEqual(actual)
  })

  it('subdirectory', () => {
    const files = ['src/App.tsx', 'src/index.css']
    const actual = buildFileTree(files)

    expect({
      src: {
        'App.tsx': null,
        'index.css': null,
      },
    }).toStrictEqual(actual)
  })

  it('all levels', () => {
    const files = ['index.html', 'src/App.tsx', 'src/styles/index.css']
    const actual = buildFileTree(files)

    expect({
      'index.html': null,
      src: {
        'App.tsx': null,
        styles: {
          'index.css': null,
        },
      },
    }).toStrictEqual(actual)
  })
})
