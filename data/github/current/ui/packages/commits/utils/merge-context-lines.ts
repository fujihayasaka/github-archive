import type {DiffLine} from '@github-ui/diff-lines'

/**
 * commit comments are positional, but that position is only relative to the original diff, so when context lines are injected
 * we need to do some funny business to line things back up.
 * we find the existing position and re-apply it to our new lines and clear out the new inaccurate position
 * @param initialDiffLines - the current diff lines
 * @param expandedDiffLines - the current diff lines with context lines injected
 * @returns DiffLine[]
 */
export function mergeContextLines(initialDiffLines: DiffLine[], expandedDiffLines: DiffLine[]) {
  const lineMap = new Map<string, (typeof initialDiffLines)[0]>()

  for (const line of initialDiffLines) {
    const key = `${line.left}-${line.right}`
    lineMap.set(key, line)
  }

  // using a map for lookups is faster than using a `find` on the array while iterating through the map
  const mergedDiffLines = expandedDiffLines.map(line => {
    const key = `${line.left}-${line.right}`
    const existingLine = lineMap.get(key)

    if (existingLine) {
      return {...line, position: existingLine.position}
    } else {
      // diffLines don't actually care about position and we can't comment on context lines anyway
      return {...line, position: null, threadsData: undefined}
    }
  })

  return mergedDiffLines
}
