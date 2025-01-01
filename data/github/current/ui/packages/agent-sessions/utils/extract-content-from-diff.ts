/**
 * Extracts the content of a file from a git diff output.
 * Currently assumes there's only one hunk in the diff.
 *
 * @param diff The git diff output
 * @returns The extracted file content
 */
export function extractContentFromDiff(diff: string | undefined): string | undefined {
  if (!diff) return undefined

  try {
    // Split the diff into lines
    const lines = diff.split('\n')
    let contentStartIndex = -1

    // Find where the actual content begins (after the diff header and hunk header)
    for (let i = 0; i < lines.length; i++) {
      // Look for the hunk header line which starts with @@
      if (lines[i]?.startsWith('@@')) {
        contentStartIndex = i + 1
        break
      }
    }
    // Extract and process the content lines, removing the leading +/- indicators
    const contentLines = lines
      .slice(contentStartIndex)
      .map(line => {
        // Keep both added and removed lines, removing the prefix and any leading space
        if (line.startsWith('+') || line.startsWith('-')) {
          // Remove the +/- prefix, then trim any single leading space if present
          const content = line.substring(1)
          return content.startsWith(' ') ? content.substring(1) : content
        } else {
          // Lines with no prefix are context lines, trim any single leading space if present
          return line.startsWith(' ') ? line.substring(1) : line
        }
      })
      .filter(line => line !== null) // Remove any null entries

    return contentLines.join('\n').trim()
  } catch {
    return diff // Return the original diff if extraction fails
  }
}
