// Takes a list of file paths and builds a recursive tree from it
// The tree has names (file and directory) as keys
// The value for a file is null
// The value for a directory is a further tree
export function buildFileTree(files: string[]): Record<string, unknown> {
  const splitFiles = files.map(file => file.split('/'))

  const result: Record<string, unknown> = {}
  for (const parts of splitFiles) {
    buildFromParts(result, parts)
  }

  return result
}

function buildFromParts(result: Record<string, unknown>, parts: string[]) {
  if (parts.length === 0) {
    return
  }

  const part = parts.shift()!
  if (parts.length === 0) {
    // Terminal file
    result[part] = null
  } else {
    // Subdirectory
    const partDir = result[part] || ({} as Record<string, unknown>)
    buildFromParts(partDir as Record<string, unknown>, parts)
    result[part] = partDir
  }
}
