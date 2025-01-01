import type {DirectoryItem} from '@github-ui/code-view-types'
import type {TreeItem} from '@github-ui/repos-file-tree-view'
import {buildTreeFromPaths} from './build-tree-from-paths'

interface FlatPathsResponse {
  paths: string[]
  directories: string[]
}

function convertTreeDataToTreeItems(
  treeData: Record<string, {items: DirectoryItem[]}>,
  path: string,
): Array<TreeItem<DirectoryItem>> {
  const directory = treeData[path]
  if (!directory) return []

  const items = directory.items.map(item => ({
    data: item,
    items: item.contentType === 'directory' ? convertTreeDataToTreeItems(treeData, item.path) : [],
  }))

  // Sort items: directories first, then alphabetical within each type
  return items.sort((a, b) => {
    if (a.data.contentType === 'directory' && b.data.contentType !== 'directory') return -1
    if (a.data.contentType !== 'directory' && b.data.contentType === 'directory') return 1
    return a.data.name.localeCompare(b.data.name)
  })
}

export function convertFlatPathsToTreeItems(response: FlatPathsResponse): Array<TreeItem<DirectoryItem>> {
  // First convert flat paths to ReposFileTreeData structure
  const treeData = buildTreeFromPaths(response)
  // Then recursively convert the tree data to TreeItem array starting from root
  return convertTreeDataToTreeItems(treeData, '')
}
