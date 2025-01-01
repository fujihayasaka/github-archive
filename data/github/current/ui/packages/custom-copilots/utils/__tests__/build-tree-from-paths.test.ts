import {buildTreeFromPaths} from '../build-tree-from-paths'
import type {ReposFileTreeData, DirectoryItem} from '@github-ui/code-view-types'

// Helper to safely get directory data
const getDirectory = (tree: ReposFileTreeData, path: string) => {
  const dir = tree[path]
  if (!dir) throw new Error(`Directory "${path}" not found in tree`)
  return dir
}

// Helper to safely get item from array
const getItem = <T>(items: T[], index: number): T => {
  const item = items[index]
  if (item === undefined) throw new Error(`Index ${index} out of bounds`)
  return item
}

describe('buildTreeFromPaths', () => {
  it('should build a tree structure from flat paths', () => {
    const input = {
      paths: [
        'README.md',
        'app',
        'app/controllers',
        'app/controllers/sample_controller.rb',
        'src',
        'src/Avatar.tsx',
        'src/file_to.exclude',
        'src/foo',
        'src/foo/bar.txt',
        'src/foo/dude',
        'src/foo/dude/sweet.text',
        'src/parser.js',
        'test',
        'test/integration',
        'test/integration/sample_controller_test.rb',
      ],
      directories: ['app', 'app/controllers', 'src', 'src/foo', 'src/foo/dude', 'test', 'test/integration'],
    }

    const result = buildTreeFromPaths(input)

    // Test root directory structure and total count (all items recursively)
    const rootDir = getDirectory(result, '')
    expect(rootDir).toBeDefined()
    expect(rootDir.items).toHaveLength(4) // README.md, app, src, test
    expect(rootDir.totalCount).toBe(15) // All items in tree

    // Test src directory recursive count
    const srcDir = getDirectory(result, 'src')
    expect(srcDir.items).toHaveLength(4) // Avatar.tsx, file_to.exclude, foo, parser.js
    expect(srcDir.totalCount).toBe(7) // 3 files + foo dir (which contains 3 items total)

    // Test src/foo directory recursive count
    const fooDir = getDirectory(result, 'src/foo')
    expect(fooDir.items).toHaveLength(2) // bar.txt and dude directory
    expect(fooDir.totalCount).toBe(3) // bar.txt + dude dir + sweet.text

    // Test deep nesting counts
    const dudeDir = getDirectory(result, 'src/foo/dude')
    expect(dudeDir.items).toHaveLength(1) // sweet.text
    expect(dudeDir.totalCount).toBe(1) // just sweet.text

    // Test app directory recursive count
    const appDir = getDirectory(result, 'app')
    expect(appDir.items).toHaveLength(1) // controllers directory
    expect(appDir.totalCount).toBe(2) // controllers dir + sample_controller.rb

    // Test test directory recursive count
    const testDir = getDirectory(result, 'test')
    expect(testDir.items).toHaveLength(1) // integration directory
    expect(testDir.totalCount).toBe(2) // integration dir + sample_controller_test.rb
  })

  it('should handle empty input', () => {
    const input = {
      paths: [],
      directories: [],
    }

    const result: ReposFileTreeData = buildTreeFromPaths(input)
    const rootDir = getDirectory(result, '')
    expect(rootDir.items).toHaveLength(0)
    expect(rootDir.totalCount).toBe(0)
  })

  it('should handle files without directories', () => {
    const input = {
      paths: ['README.md', 'package.json'],
      directories: [],
    }

    const result: ReposFileTreeData = buildTreeFromPaths(input)
    const rootDir = getDirectory(result, '')
    expect(rootDir.items).toHaveLength(2)
    expect(rootDir.items.map(item => item.name)).toEqual(['package.json', 'README.md'])
    expect(rootDir.items.every(item => item.contentType === 'file')).toBe(true)
  })

  it('should build a correctly structured and ordered tree from flat paths', () => {
    const input = {
      paths: [
        'README.md',
        'src/index.ts',
        'src/components/Button.tsx',
        'src/components/Input.tsx',
        'src/utils/helper.ts',
      ],
      directories: ['src', 'src/components', 'src/utils'],
    }

    const result = buildTreeFromPaths(input)

    // Check root directory
    const rootDir = getDirectory(result, '')
    expect(rootDir.items).toHaveLength(2) // README.md and src
    expect(rootDir.totalCount).toBe(8)

    // Verify root level items ordering (directories before files)
    const rootItems = rootDir.items
    const firstItem = getItem(rootItems, 0)
    const secondItem = getItem(rootItems, 1)

    expect(firstItem.contentType).toBe('directory')
    expect(firstItem.name).toBe('src')
    expect(secondItem.contentType).toBe('file')
    expect(secondItem.name).toBe('README.md')

    // Check src directory
    const srcDir = getDirectory(result, 'src')
    expect(srcDir.items).toHaveLength(3) // components, utils, index.ts
    expect(srcDir.totalCount).toBe(6)

    // Verify src directory ordering (directories before files, alphabetical within types)
    const srcItems = srcDir.items
    expect(srcItems.map(item => ({name: item.name, type: item.contentType}))).toEqual([
      {name: 'components', type: 'directory'},
      {name: 'utils', type: 'directory'},
      {name: 'index.ts', type: 'file'},
    ])

    // Check src/components directory
    const componentsDir = getDirectory(result, 'src/components')
    expect(componentsDir.items).toHaveLength(2)
    expect(componentsDir.totalCount).toBe(2)

    // Verify src/components ordering (alphabetical for files)
    const componentItems = componentsDir.items
    expect(componentItems.map(item => item.name)).toEqual(['Button.tsx', 'Input.tsx'])
    expect(componentItems.every(item => item.contentType === 'file')).toBe(true)

    // Check src/utils directory
    const utilsDir = getDirectory(result, 'src/utils')
    expect(utilsDir.items).toHaveLength(1)
    expect(utilsDir.totalCount).toBe(1)
    expect(utilsDir.items[0]).toEqual({
      name: 'helper.ts',
      path: 'src/utils/helper.ts',
      contentType: 'file',
    })
  })

  it('should maintain correct parent-child relationships', () => {
    const input = {
      paths: ['app/controllers/api/v1/users_controller.rb', 'app/controllers/api/v2/users_controller.rb'],
      directories: [
        'app',
        'app/controllers',
        'app/controllers/api',
        'app/controllers/api/v1',
        'app/controllers/api/v2',
      ],
    }

    const result = buildTreeFromPaths(input)

    // Test directory hierarchy
    const rootDir = getDirectory(result, '')
    const app = rootDir.items.find(i => i.name === 'app') as DirectoryItem
    expect(app).toBeDefined()
    expect(app.contentType).toBe('directory')

    const appDir = getDirectory(result, 'app')
    const controllers = appDir.items.find(i => i.name === 'controllers') as DirectoryItem
    expect(controllers).toBeDefined()
    expect(controllers.contentType).toBe('directory')

    const controllersDir = getDirectory(result, 'app/controllers')
    const api = controllersDir.items.find(i => i.name === 'api') as DirectoryItem
    expect(api).toBeDefined()
    expect(api.contentType).toBe('directory')

    // Test v1 and v2 are in correct order
    const apiDir = getDirectory(result, 'app/controllers/api')
    const apiItems = apiDir.items
    expect(apiItems.map(i => i.name)).toEqual(['v1', 'v2'])

    // Test files are in their correct directories
    const v1Dir = getDirectory(result, 'app/controllers/api/v1')
    const v2Dir = getDirectory(result, 'app/controllers/api/v2')
    expect(getItem(v1Dir.items, 0).name).toBe('users_controller.rb')
    expect(getItem(v2Dir.items, 0).name).toBe('users_controller.rb')
  })

  it('should calculate correct recursive counts in deep hierarchies', () => {
    const input = {
      paths: [
        'app/controllers/api/v1/users_controller.rb',
        'app/controllers/api/v2/users_controller.rb',
        'app/models/user.rb',
      ],
      directories: [
        'app',
        'app/controllers',
        'app/controllers/api',
        'app/controllers/api/v1',
        'app/controllers/api/v2',
        'app/models',
      ],
    }

    const result = buildTreeFromPaths(input)

    // Root should count everything
    const rootDir = getDirectory(result, '')
    expect(rootDir.totalCount).toBe(9) // app + all subdirs + all files

    // app directory should count everything under it
    const appDir = getDirectory(result, 'app')
    expect(appDir.totalCount).toBe(8) // controllers & models dirs + all their contents

    // controllers directory counts
    const controllersDir = getDirectory(result, 'app/controllers')
    expect(controllersDir.totalCount).toBe(5) // api dir + v1/v2 dirs + 2 controller files

    // api directory counts
    const apiDir = getDirectory(result, 'app/controllers/api')
    expect(apiDir.totalCount).toBe(4) // v1/v2 dirs + 2 controller files

    // v1 and v2 directories each have 1 file
    const v1Dir = getDirectory(result, 'app/controllers/api/v1')
    const v2Dir = getDirectory(result, 'app/controllers/api/v2')
    expect(v1Dir.totalCount).toBe(1)
    expect(v2Dir.totalCount).toBe(1)

    // models directory has 1 file
    const modelsDir = getDirectory(result, 'app/models')
    expect(modelsDir.totalCount).toBe(1)
  })
})
