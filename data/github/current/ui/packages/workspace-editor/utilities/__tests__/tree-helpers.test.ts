import type {ReposFileTreeData} from '@github-ui/code-view-types'

import {addPathToTree, removePathFromTree} from '../tree-helpers'

const fileTreeData: ReposFileTreeData = {
  '': {
    items: [
      {
        contentType: 'directory',
        name: 'public',
        path: 'public',
      },
      {
        contentType: 'directory',
        name: 'src',
        path: 'src',
      },
      {contentType: 'file', name: 'readme.md', path: 'readme.md'},
    ],
    totalCount: 3,
  },
  public: {
    items: [
      {
        contentType: 'file',
        name: 'favicon.ico',
        path: 'public/favicon.ico',
      },
    ],
    totalCount: 1,
  },
  src: {
    items: [
      {
        contentType: 'directory',
        name: 'components',
        path: 'src/components',
      },
    ],
    totalCount: 1,
  },
  'src/components': {
    items: [
      {
        contentType: 'file',
        name: 'button.ts',
        path: 'src/components/button.ts',
      },
    ],
    totalCount: 1,
  },
}

describe('addPathToTree', () => {
  test('adds file to existing directory in correct order', () => {
    const data = {...fileTreeData}
    addPathToTree(data, 'src/index.js')
    expect(data['src']!.items.length).toBe(2)
    expect(data['src']!.totalCount).toBe(2)
    expect(data['src']!.items[1]!.name).toBe('index.js')
    expect(data['src']!.items[1]!.path).toBe('src/index.js')
  })

  test('adds file to base directory in correct order', () => {
    const data = {...fileTreeData}
    addPathToTree(data, 'index.js')
    expect(data['']!.items.length).toBe(4)
    expect(data['']!.totalCount).toBe(4)
    expect(data['']!.items[2]!.name).toBe('index.js')
    expect(data['']!.items[2]!.path).toBe('index.js')
  })

  test('adds directory to existing directory in correct', () => {
    const data = {...fileTreeData}
    addPathToTree(data, 'src/path/index.js')
    expect(data['']!.items.length).toBe(3)
    expect(data['src']!.items.length).toBe(2)
    expect(data['src']!.totalCount).toBe(2)
    expect(data['src']!.items[1]!.name).toBe('path')
    expect(data['src']!.items[1]!.name).toBe('path')
    expect(data['src']!.items[1]!.path).toBe('src/path')
  })

  test('adds directory to base directory in correct order', () => {
    const data = {...fileTreeData}
    addPathToTree(data, 'new/path/index.js')
    expect(data['']!.items.length).toBe(4)
    expect(data['']!.items[0]!.name).toBe('new')
    expect(data['']!.items[0]!.path).toBe('new')
    expect(data['new']).toBeUndefined()
    expect(data['new/path']).toBeUndefined()
  })

  test('adds full path to existing directory in correct order', () => {
    const data = {...fileTreeData}
    addPathToTree(data, 'src/components/new/button.ts', true)
    expect(data['']!.items.length).toBe(3)
    expect(data['']!.totalCount).toBe(3)
    expect(data['src/components']!.items.length).toBe(2)
    expect(data['src/components']!.totalCount).toBe(2)
    expect(data['src/components']!.items[0]!.name).toBe('new')
    expect(data['src/components']!.items[0]!.path).toBe('src/components/new')
    expect(data['src/components/new']!.items.length).toBe(1)
    expect(data['src/components/new']!.totalCount).toBe(1)
    expect(data['src/components/new']!.items[0]!.name).toBe('button.ts')
    expect(data['src/components/new']!.items[0]!.path).toBe('src/components/new/button.ts')
  })

  test('adds full path to base directory in correct order', () => {
    const data = {...fileTreeData}
    addPathToTree(data, 'path/to/new/button.ts', true)
    expect(data['']!.items.length).toBe(4)
    expect(data['']!.totalCount).toBe(4)
    expect(data['']!.items[0]!.name).toBe('path/to/new')
    expect(data['']!.items[0]!.path).toBe('path/to/new')
    expect(data['path']).toBeUndefined()
    expect(data['path/to']).toBeUndefined()
    expect(data['path/to/new']!.items.length).toBe(1)
    expect(data['path/to/new']!.totalCount).toBe(1)
    expect(data['path/to/new']!.items[0]!.name).toBe('button.ts')
    expect(data['path/to/new']!.items[0]!.path).toBe('path/to/new/button.ts')
  })
})

describe('removePathFromTree', () => {
  test('removes file from base directory', () => {
    const data = {...fileTreeData}
    removePathFromTree(data, 'readme.md')
    expect(data['']!.items.length).toBe(2)
    expect(data['']!.totalCount).toBe(2)
    expect(data['']!.items.find(item => item.path === 'readme.md')).toBeUndefined()
  })

  test('removes file from existing directory and leaves parent directory that has more items', () => {
    const data = {...fileTreeData}

    data['src/components'] = {
      items: [
        ...data['src/components']!.items,
        {
          contentType: 'file',
          name: 'button2.ts',
          path: 'src/components/button2.ts',
        },
      ],
      totalCount: data['src']!.totalCount + 1,
    }

    removePathFromTree(data, 'src/components/button.ts')

    // only item in the directory, so the directory gets recursively removed
    expect(data['src/components']).toBeDefined()
    expect(data['src/components'].items.length).toBe(1)
    expect(data['src/components'].totalCount).toBe(1)
    expect(data['src/components'].items.find(item => item.path === 'src/components/button2.ts')).toBeDefined()
    expect(data['src/components'].items.find(item => item.path === 'button.ts')).toBeUndefined()
    expect(data['src']).toBeDefined()
    expect(data['']!.items.length).toBe(3)
    expect(data['']!.totalCount).toBe(3)
    expect(data['']!.items.find(item => item.path === 'src')).toBeDefined()
  })

  test('removes file from existing directory and recursively removes all empty parent directories', () => {
    const data = {...fileTreeData}
    removePathFromTree(data, 'src/components/button.ts')

    // only item in the directory, so the directory gets recursively removed
    expect(data['src/components']).toBeUndefined()
    expect(data['src']).toBeUndefined()
    expect(data['']!.items.length).toBe(2)
    expect(data['']!.totalCount).toBe(2)
    expect(data['']!.items.find(item => item.path === 'src')).toBeUndefined()
  })

  test('removes file from existing directory and recursively removes two parent directories', () => {
    const data = {...fileTreeData}

    data['src'] = {
      items: [
        ...data['src']!.items,
        {
          contentType: 'file',
          name: 'button2.ts',
          path: 'src/button2.ts',
        },
      ],
      totalCount: data['src']!.totalCount + 1,
    }

    removePathFromTree(data, 'src/components/button.ts')

    expect(data['src/components']).toBeUndefined()
    expect(data['src']).toBeDefined()
    expect(data['src'].items.length).toBe(1)
    expect(data['src'].totalCount).toBe(1)
    expect(data['src'].items.find(item => item.path === 'src/button2.ts')).toBeDefined()
    expect(data['src'].items.find(item => item.path === 'src/components')).toBeUndefined()
    expect(data['src']).toBeDefined()
    expect(data['']!.items.length).toBe(3)
    expect(data['']!.totalCount).toBe(3)
    expect(data['']!.items.find(item => item.path === 'src')).toBeDefined()
  })

  test('removing multiple files at a time', () => {
    const data = {...fileTreeData}

    data['src/components'] = {
      items: [
        ...data['src/components']!.items,
        {
          contentType: 'file',
          name: 'button2.ts',
          path: 'src/components/button2.ts',
        },
      ],
      totalCount: data['src']!.totalCount + 1,
    }

    removePathFromTree(data, 'src/components/button.ts')
    removePathFromTree(data, 'src/components/button2.ts')

    // only item in the directory, so the directory gets recursively removed
    expect(data['src/components']).toBeUndefined()
    expect(data['src']).toBeUndefined()
    expect(data['']!.items.length).toBe(2)
    expect(data['']!.totalCount).toBe(2)
    expect(data['']!.items.find(item => item.path === 'src')).toBeUndefined()
  })
})
