import type {DiffLine} from '@github-ui/diffs/types'
import type {DiffData, DiffHunk} from './types'

export function parseDiffsToHunks(diffs: DiffData[]): DiffHunk[] {
  const localHunks: DiffHunk[] = []

  for (const diff of diffs) {
    if (diff.isBinary || diff.isTooBig) continue

    type HunkData = {
      oldStart: number
      oldEnd: number
      newStart: number
      newEnd: number
      lines: DiffLine[]
    }

    // Parse each file's diff lines into separate hunks
    let currentHunk: HunkData | null = null

    for (const line of diff.diffLines) {
      // Start a new hunk when we hit a hunk header
      if (line.type === 'HUNK') {
        // If we have a current hunk, add it to localHunks
        if (currentHunk) {
          const lineCountOld = currentHunk.oldEnd - currentHunk.oldStart
          const lineCountNew = currentHunk.newEnd - currentHunk.newStart
          const hunkId = `${diff.path}:${currentHunk.oldStart}-${currentHunk.oldEnd}:${currentHunk.newStart}-${currentHunk.newEnd}`
          localHunks.push({
            hunkId,
            filePath: diff.path,
            hunkTitle: `@@ -${currentHunk.oldStart},${lineCountOld} +${currentHunk.newStart},${lineCountNew} @@`,
            lines: currentHunk.lines,
            rawUnifiedDiff: currentHunk.lines
              .map(lineItem => {
                const prefix = lineItem.type === 'ADDITION' ? '+' : lineItem.type === 'DELETION' ? '-' : ' '
                return prefix + lineItem.text
              })
              .join('\n'),
            modificationType: diff.status.toLowerCase() as 'added' | 'deleted' | 'modified' | 'renamed',
          })
        }

        // Parse hunk header to get line numbers
        // Format is @@ -oldStart,oldLines +newStart,newLines @@
        const match = line.text.match(/@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/)
        if (match && match[1] && match[2]) {
          const oldStart = parseInt(match[1], 10)
          const newStart = parseInt(match[2], 10)

          currentHunk = {
            oldStart,
            oldEnd: oldStart,
            newStart,
            newEnd: newStart,
            lines: [line],
          }
        }
      } else if (currentHunk) {
        // Add line to current hunk and update line counts
        currentHunk.lines.push(line)
        if (line.type === 'DELETION') {
          currentHunk.oldEnd++
        }
        if (line.type === 'ADDITION') {
          currentHunk.newEnd++
        }
        if (line.type === 'CONTEXT') {
          currentHunk.oldEnd++
          currentHunk.newEnd++
        }
      }
    }

    // Add the final hunk if there is one
    if (currentHunk) {
      const lineCountOld = currentHunk.oldEnd - currentHunk.oldStart
      const lineCountNew = currentHunk.newEnd - currentHunk.newStart
      const hunkId = `${diff.path}:${currentHunk.oldStart}-${currentHunk.oldEnd}:${currentHunk.newStart}-${currentHunk.newEnd}`
      localHunks.push({
        hunkId,
        filePath: diff.path,
        hunkTitle: `@@ -${currentHunk.oldStart},${lineCountOld} +${currentHunk.newStart},${lineCountNew} @@`,
        lines: currentHunk.lines,
        rawUnifiedDiff: currentHunk.lines
          .map(lineItem => {
            const prefix = lineItem.type === 'ADDITION' ? '+' : lineItem.type === 'DELETION' ? '-' : ' '
            return prefix + lineItem.text
          })
          .join('\n'),
        modificationType: diff.status.toLowerCase() as 'added' | 'deleted' | 'modified' | 'renamed',
      })
    }
  }

  return localHunks
}
