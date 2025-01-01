import type {DirectoryItem, ReposFileTreeData} from '@github-ui/code-view-types'

interface FlatPathsResponse {
  paths: string[]
  directories: string[]
}

export function buildTreeFromPaths(response: FlatPathsResponse): ReposFileTreeData {
  const {paths, directories} = response
  const treeData: ReposFileTreeData = {}
  const directorySet = new Set(directories)

  // Initialize root directory
  treeData[''] = {
    items: [],
    totalCount: 0,
  }

  // Sort directories first to ensure consistent order
  const sortedDirectories = [...directories].sort()

  // First, process all directories
  for (const dirPath of sortedDirectories) {
    const parentPath = dirPath.substring(0, dirPath.lastIndexOf('/')) || ''
    const dirName = dirPath.substring(dirPath.lastIndexOf('/') + 1)

    // Create directory item
    const dirItem: DirectoryItem = {
      name: dirName,
      path: dirPath,
      contentType: 'directory',
    }

    // Ensure parent directory exists
    if (!treeData[parentPath]) {
      treeData[parentPath] = {
        items: [],
        totalCount: 0,
      }
    }

    // Add directory to parent's items
    treeData[parentPath].items.push(dirItem)

    // Initialize this directory's entry
    if (!treeData[dirPath]) {
      treeData[dirPath] = {
        items: [],
        totalCount: 0,
      }
    }
  }

  // Sort paths to ensure consistent order of files
  const sortedPaths = paths.filter(p => !directorySet.has(p)).sort()

  // Process all files
  for (const filePath of sortedPaths) {
    const parentPath = filePath.substring(0, filePath.lastIndexOf('/')) || ''
    const fileName = filePath.substring(filePath.lastIndexOf('/') + 1)

    // Create file item
    const fileItem: DirectoryItem = {
      name: fileName,
      path: filePath,
      contentType: 'file',
    }

    // Ensure parent directory exists
    if (!treeData[parentPath]) {
      treeData[parentPath] = {
        items: [],
        totalCount: 0,
      }
    }

    // Add file to parent's items
    treeData[parentPath].items.push(fileItem)
  }

  // Sort items in each directory
  for (const dirPath in treeData) {
    const dirData = treeData[dirPath]
    if (!dirData) continue

    dirData.items.sort((a, b) => {
      // Directories come before files
      if (a.contentType === 'directory' && b.contentType !== 'directory') return -1
      if (a.contentType !== 'directory' && b.contentType === 'directory') return 1
      // Sort by name within same type
      return a.name.localeCompare(b.name)
    })
  }

  // Calculate recursive totalCount for each directory
  const calculateTotalCount = (path: string): number => {
    const dir = treeData[path]
    if (!dir) return 0

    // Count direct children plus recursive count of subdirectories
    return dir.items.reduce((total, item) => {
      if (item.contentType === 'directory') {
        return total + 1 + calculateTotalCount(item.path)
      }
      return total + 1
    }, 0)
  }

  // Update totalCount for each directory
  for (const dirPath in treeData) {
    const dirData = treeData[dirPath]
    if (!dirData) continue

    dirData.totalCount = calculateTotalCount(dirPath)
  }

  return treeData
}
