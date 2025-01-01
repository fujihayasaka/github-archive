import type {TreeItem} from '@github-ui/repos-file-tree-view'
import type {DirectoryItem} from '@github-ui/code-view-types'
import {convertFlatPathsToTreeItems} from '../convert-tree-data'

// Helper to safely get item from array
const getItem = <T>(items: T[], index: number): T => {
  const item = items[index]
  if (item === undefined) throw new Error(`Index ${index} out of bounds`)
  return item
}

// Helper to safely find item in array
const findItem = (items: Array<TreeItem<DirectoryItem>>, name: string): TreeItem<DirectoryItem> => {
  const found = items.find(i => i.data.name === name)
  if (!found) throw new Error(`Item "${name}" not found`)
  return found
}

describe('convertFlatPathsToTreeItems', () => {
  it('should convert flat paths into root-level tree items', () => {
    const input = {
      paths: [
        'README.md',
        'app',
        'app/controllers',
        'app/controllers/sample_controller.rb',
        'src',
        'src/Avatar.tsx',
        'src/parser.js',
        'src/foo',
        'src/foo/bar.txt',
        'src/foo/dude',
        'src/foo/dude/sweet.text',
      ],
      directories: ['app', 'app/controllers', 'src', 'src/foo', 'src/foo/dude'],
    }

    const result = convertFlatPathsToTreeItems(input)

    // Test that root items were created
    expect(result.length).toBe(3) // README.md, app, src

    // Test root items are in correct order (directories first, then files)
    expect(result.map(item => item.data.name)).toEqual(['app', 'src', 'README.md'])

    // Test item types and paths using safe accessors
    const [appDir, srcDir, readmeFile] = [
      findItem(result, 'app'),
      findItem(result, 'src'),
      findItem(result, 'README.md'),
    ]

    expect(appDir.data.contentType).toBe('directory')
    expect(srcDir.data.contentType).toBe('directory')
    expect(readmeFile.data.contentType).toBe('file')

    expect(appDir.data.path).toBe('app')
    expect(srcDir.data.path).toBe('src')
    expect(readmeFile.data.path).toBe('README.md')
  })

  it('should recursively populate items for directories', () => {
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

    const result = convertFlatPathsToTreeItems(input)

    // Test root structure (directories before files)
    expect(result.length).toBe(2) // README.md and src
    expect(result.map(item => item.data.name)).toEqual(['src', 'README.md'])

    // Get src directory using safe accessor
    const srcDir = findItem(result, 'src')
    expect(srcDir).toBeDefined()
    expect(srcDir.items.length).toBe(3) // index.ts, components, utils

    // Verify src contents (directories before files)
    expect(srcDir.items.map(item => item.data.name)).toEqual(['components', 'utils', 'index.ts'])

    // Test components directory
    const componentsDir = findItem(srcDir.items, 'components')
    expect(componentsDir).toBeDefined()
    expect(componentsDir.items.length).toBe(2)
    expect(componentsDir.items.map(item => item.data.name)).toEqual(['Button.tsx', 'Input.tsx'])

    // Test utils directory
    const utilsDir = findItem(srcDir.items, 'utils')
    expect(utilsDir).toBeDefined()
    expect(utilsDir.items.length).toBe(1)
    expect(getItem(utilsDir.items, 0).data.name).toBe('helper.ts')
  })

  it('should handle empty input', () => {
    const result = convertFlatPathsToTreeItems({paths: [], directories: []})
    expect(result).toEqual([])
  })
})
