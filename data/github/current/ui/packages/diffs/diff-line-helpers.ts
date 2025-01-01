import type {DiffLineType, SimpleDiffLine} from './types'

/**
 * Prefix the line anchor to prevent the browser from jumping to the element when we update the hash.
 */
export function lineIdentifierFrom(anchor: string) {
  return `line-${anchor}`
}

/**
 * Returns the line anchor based on the file anchor, orientation, and line number
 */
export function lineAnchorFrom(fileAnchor: string, orientation: 'left' | 'right', lineNumber: number) {
  return `${fileAnchor}${orientation === 'left' ? 'L' : 'R'}${lineNumber}`
}

/**
 * Returns the line orientation from the diff line type
 */
export function lineOrientationFrom(type: DiffLineType) {
  return type === 'DELETION' ? 'left' : 'right'
}

/**
 * Returns the background color based on the line type
 */
export function getBackgroundColor(
  lineType: DiffLineType,
  isNumber = false,
  isHighlighted = false,
): string | undefined {
  if (isHighlighted) return 'var(--bgColor-attention-muted, var(--color-attention-subtle))'

  switch (lineType) {
    case 'ADDITION':
      return isNumber
        ? 'var(--diffBlob-additionNum-bgColor, var(--diffBlob-addition-bgColor-num))'
        : 'var(--diffBlob-additionLine-bgColor, var(--diffBlob-addition-bgColor-line))'
    case 'DELETION':
      return isNumber
        ? 'var(--diffBlob-deletionNum-bgColor, var(--diffBlob-deletion-bgColor-num))'
        : 'var(--diffBlob-deletionLine-bgColor, var(--diffBlob-deletion-bgColor-line))'
    case 'HUNK':
      return isNumber
        ? 'var(--diffBlob-hunkNum-bgColor, var(--diffBlob-hunk-bgColor-num))'
        : 'var(--diffBlob-hunkLine-bgColor, var(--bgColor-accent-muted))'
    case 'EMPTY':
      return isNumber
        ? 'var(--diffBlob-emptyNum-bgColor, var(--diffBlob-hunk-bgColor-num))'
        : 'var(--diffBlob-emptyLine-bgColor, var(--bgColor-accent-muted))'
    default:
      return undefined
  }
}

/**
 * Get the largest line number, then return the width of the line number column using it
 */
export function getLineNumberWidth(lines: Array<SimpleDiffLine | null> | null): string {
  let maxLineNumber = 0
  if (lines) {
    for (const line of lines) {
      maxLineNumber = Math.max(maxLineNumber, line?.left ?? 0, line?.right ?? 0)
    }
  }

  // 8 pixels per character plus 20 for horizontal padding
  const lineNumberPxWidth = maxLineNumber.toString().length * 8 + 20
  return Math.max(lineNumberPxWidth, 40).toString()
}
