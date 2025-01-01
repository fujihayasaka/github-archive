import {lineOrientationFrom} from '@github-ui/diffs/diff-line-helpers'
import type {DiffAnchor, DiffLineType, SimpleDiffLine} from '@github-ui/diffs/types'
import {isMacOS} from '@github-ui/get-os'

import type {DiffLine, ClientDiffLine, LineRange, EmptyDiffLine} from '../types'
import type {SelectedDiffLines} from '../contexts/SelectedDiffRowRangeContext'
import {EMPTY_DIFF_LINE} from '../types'
import {urlHashFromLineRange} from './document-hash-helpers'

export type OutdatedDiffLine = Omit<DiffLine, 'threads' | 'blobLineNumber'>

export type DiffSide = 'LEFT' | 'RIGHT'

export function matchLine(
  line: ClientDiffLine,
  lineNumber: number | undefined,
  orientation: 'left' | 'right' | undefined,
): boolean {
  switch (orientation) {
    case 'left':
      return !isEmptyDiffLine(line) && line.left === lineNumber
    case 'right':
    default:
      return !isEmptyDiffLine(line) && lineOrientationFrom(line.type) === orientation && line.right === lineNumber
  }
}

/**
 * Compare a line range to a list of lines. If the start of the range comes after the end, we'll flip it and return
 * a new range with the correct ordering.
 */
export function orderLineRange(
  lineRange: LineRange | undefined,
  lines: Array<DiffLine | null> | null,
): LineRange | undefined {
  if (!lineRange) return undefined
  if (!lines) return lineRange

  let outOfOrder = false
  let foundStart = false
  let foundEnd = false
  for (const line of lines) {
    if (!line) continue

    foundStart ||= matchLine(line, lineRange.startLineNumber, lineRange.startOrientation)
    foundEnd ||= matchLine(line, lineRange.endLineNumber, lineRange.endOrientation)
    outOfOrder = foundEnd && !foundStart
    if (outOfOrder || (foundStart && foundEnd)) break
  }

  if (outOfOrder) {
    return {
      ...lineRange,
      startLineNumber: lineRange.endLineNumber,
      startOrientation: lineRange.endOrientation,
      endLineNumber: lineRange.startLineNumber,
      endOrientation: lineRange.startOrientation,
    }
  } else {
    return lineRange
  }
}

export function rowIdFrom(fileAnchor: string, leftLine: ClientDiffLine, rightLine?: ClientDiffLine) {
  const leftLinePart = `-${isEmptyDiffLine(leftLine) || typeof leftLine.left !== 'number' ? 'empty' : leftLine.left}`
  const rightLinePart = rightLine
    ? `-${isEmptyDiffLine(rightLine) || typeof rightLine.right !== 'number' ? 'empty' : rightLine.right}`
    : ''

  return `${fileAnchor}${leftLinePart}${rightLinePart}`
}

export function cellIdFrom(rowId: string, columnIndex: number) {
  return `${rowId}-${columnIndex}`
}

export function isEmptyDiffLine(diffLine?: ClientDiffLine): diffLine is EmptyDiffLine {
  return !!diffLine && diffLine === EMPTY_DIFF_LINE
}

export function isDiffLine(diffLine?: ClientDiffLine): diffLine is DiffLine {
  return !!diffLine && diffLine !== EMPTY_DIFF_LINE
}

export function isContextDiffLine(diffLine: DiffLine): boolean {
  return diffLine.type === 'CONTEXT'
}

/*
 * Diff lines are prepended by a character depending on type (see lib/github/diff/enumerator.rb#L16).
 * Ideally, this character is trimmed from the diff line html string on the server-side. However, there are two cases
 * where we need to handle this on the client-side instead:
 *   1. When line type character isn't trimmed from DiffLine.html on the server-side (true for DiffLine payloads
 *      generated from `Commit::ReactDiffLinesHelper#build_diff_line_data`).
 *   2. When `lineContent` argument passed into this function is DiffLine.text instead of DiffLine.html. The line type
 *      character should never be trimmed from DiffLine.text on the server, so we have to handle it here.
 *
 * This function trims the line type character from the given `lineContent` string if present, based on given
 * `lineType`, and returns the trimmed content along with the removed character (if any).
 */
export function trimContentLine(
  lineContent: string, // DiffLine.text or DiffLine.html
  lineType: DiffLineType,
  injectedContextBugfixEnabled: boolean = false,
): [lineContent: string, removedChar?: string] {
  if (injectedContextBugfixEnabled) {
    return candidateTrimContentLine(lineContent, lineType)
  }
  return controlTrimContentLine(lineContent, lineType)
}

function controlTrimContentLine(
  lineContent: string,
  lineType: DiffLineType,
): [lineContent: string, removedChar?: string] {
  let charToRemove: string | undefined

  switch (lineType) {
    case 'ADDITION':
      charToRemove = '+'
      break
    case 'DELETION':
      charToRemove = '-'
      break
    case 'CONTEXT':
    case 'INJECTED_CONTEXT':
      charToRemove = ' '
      break
  }

  if (!charToRemove || !lineContent.startsWith(charToRemove)) return [lineContent, undefined]

  const removedChar = lineContent[0]
  const newLineContent = lineContent.substring(1)
  return [newLineContent, removedChar]
}

function candidateTrimContentLine(
  lineContent: string,
  lineType: DiffLineType,
): [lineContent: string, removedChar?: string] {
  let lineTypeCharactersToTrim: string[] | undefined

  switch (lineType) {
    case 'ADDITION':
      lineTypeCharactersToTrim = ['+']
      break
    case 'DELETION':
      lineTypeCharactersToTrim = ['-']
      break
    case 'CONTEXT':
      lineTypeCharactersToTrim = [' ']
      break
    // Technically, INJECTED_CONTEXT line types should only ever start with a tilde (~) character, but for unknown
    // reasons, in some cases, they're prefaced with a space, so we need to handle that as well.
    case 'INJECTED_CONTEXT':
      lineTypeCharactersToTrim = [' ', '~']
      break
  }

  if (lineTypeCharactersToTrim === undefined || lineTypeCharactersToTrim.length === 0) {
    // No line type characters to trim, return the original content
    return [lineContent, undefined]
  }

  if (lineTypeCharactersToTrim.every(lineTypeCharacter => !lineContent.startsWith(lineTypeCharacter))) {
    // Line content doesn't start with any of the line type characters, return the original content
    return [lineContent, undefined]
  }

  const removedChar = lineContent[0]
  const newLineContent = lineContent.substring(1)
  return [newLineContent, removedChar]
}

export function groupDiffLines(lines: DiffLine[]): {
  leftLines: ClientDiffLine[]
  rightLines: ClientDiffLine[]
} {
  const leftLines: ClientDiffLine[] = []
  const rightLines: ClientDiffLine[] = []

  // Keep list of lines even, filling in blanks as needed
  const fillBlanks = () => {
    while (leftLines.length < rightLines.length) {
      leftLines.push(EMPTY_DIFF_LINE)
    }

    while (rightLines.length < leftLines.length) {
      rightLines.push(EMPTY_DIFF_LINE)
    }
  }

  for (const line of lines) {
    switch (line.type) {
      case 'ADDITION':
        rightLines.push(line)
        break
      case 'DELETION':
        leftLines.push(line)
        break
      case 'CONTEXT':
      case 'INJECTED_CONTEXT':
      case 'HUNK':
        fillBlanks()
        leftLines.push(line)
        rightLines.push(line)
    }
  }

  fillBlanks()

  return {leftLines, rightLines}
}

export function parseHtml(html: string) {
  return new DOMParser().parseFromString(html, 'text/html').documentElement.textContent || ''
}

export function isLeftLine(line: SimpleDiffLine) {
  const leftLineTypes = ['HUNK', 'CONTEXT', 'INJECTED_CONTEXT', 'DELETION']

  return leftLineTypes.includes(line.type)
}

export function urlHashFromLine(line: SimpleDiffLine, fileAnchor: string): string | undefined {
  const leftLine = isLeftLine(line)
  const lineNumber = leftLine ? line.left : line.right
  const orientation = leftLine ? 'left' : 'right'

  if (lineNumber !== null) {
    return urlHashFromLineRange({
      diffAnchor: fileAnchor,
      endLineNumber: lineNumber,
      endOrientation: orientation,
      startLineNumber: lineNumber,
      startOrientation: orientation,
      firstSelectedLineNumber: lineNumber,
      firstSelectedOrientation: orientation,
    })
  }

  return
}

// Get the link for a line or a selected range of lines
export function anchorLinkForSelection({
  line,
  range,
  fileAnchor,
}: {
  line?: SimpleDiffLine
  range?: LineRange
  fileAnchor: DiffAnchor
}): string | undefined {
  const {origin, pathname} = window.location
  let hash
  if (range) {
    hash = urlHashFromLineRange(range)
  } else if (line) {
    hash = urlHashFromLine(line, fileAnchor)
  }

  if (!hash) return

  return `${origin}${pathname}#${hash}`
}

export type KeyboardShortcutArgs = {
  includeControlKey?: boolean
  includeShiftKey?: boolean
  includeOptionKey?: boolean
  key: string
}

/**
 * Returns a string representing a keyboard shortcut, including the Control key by default. Adds formatting for specific OS (MacOS vs Windows) so it looks a little nicer.
 * @param includeControlKey Whether to include the Control key in the shortcut string. Defaults to true.
 * @param includeShiftKey Whether to include the Shift key in the shortcut string. Defaults to false.
 * @param includeOptionKey Whether to include the Option key in the shortcut string. Defaults to false.
 * @param key The key to include in the shortcut string.
 */
export function getKeyboardShortcutString({
  includeControlKey = true,
  includeShiftKey,
  includeOptionKey,
  key,
}: KeyboardShortcutArgs) {
  let str = includeControlKey ? `${isMacOS() ? '⌘' : 'Ctrl + '}` : ''
  if (includeOptionKey) str += `${isMacOS() ? '⌥' : 'Alt + '}`
  if (includeShiftKey) str += `${isMacOS() ? '⇧' : 'Shift + '}`
  str += key
  return str
}

/**
 * Returns a string representing the pixel width of a gutter to account for the CommentIndicator and ActionBar components to render without overlapping over the code content.
 * This will default to 96px if there is a thread count of 1 or more.
 * This does not account for number of author avatars, but will render the necessary amount of space for 3 avatar icons stacked in the CommentIndicator and ActionBar components.
 * @param hasThreads A boolean that indicates if the diff line has any associated threads.
 */
export function calculateDiffLineCodeCellGutter({hasThreads}: {hasThreads: boolean}) {
  return hasThreads ? '80px' : '24px'
}

/**
 * Returns a string representing a valid aria-keyshortcuts value, including OS specific keys.
 * @param includeControlKey Whether to include the Control key in the shortcut string. Defaults to true.
 * @param includeShiftKey Whether to include the Shift key in the shortcut string. Defaults to false.
 * @param includeOptionKey Whether to include the Option key in the shortcut string. Defaults to false.
 * @param key The key to include in the shortcut string.
 */
export function getAriaKeyShortcutString({
  includeControlKey = true,
  includeShiftKey,
  includeOptionKey,
  key,
}: KeyboardShortcutArgs) {
  let str = ''
  if (includeControlKey) str += isMacOS() ? 'Command+' : 'Control+'
  if (includeOptionKey) str += isMacOS() ? 'Option+' : 'Alt+'
  if (includeShiftKey) str += 'Shift+'
  str += key
  return str
}

const LINE_TYPES_SUPPORTING_COMMENTS = ['ADDITION', 'DELETION', 'CONTEXT']

/**
 * Detemines if the given diff line supports commenting. If the diff line is part of the current selected
 * range then all lines must be commentable for the diff line to be displayed as commentable.
 * @param diffLine The current diff line being rendered
 * @param selectedDiffLines The left and right diff lines that are currently selected, if any
 */
export const lineAcceptsComments = (
  diffLine: ClientDiffLine | undefined,
  selectedDiffLines: SelectedDiffLines,
): boolean => {
  if (!diffLine) return false

  const selectedLines = selectedDiffLines.leftLines.concat(selectedDiffLines.rightLines)
  if (selectedLines.length > 0 && selectedLines.includes(diffLine)) {
    // current line is within selected range - are all lines commentable?
    return selectedLines.every(line => {
      return !isEmptyDiffLine(line) && LINE_TYPES_SUPPORTING_COMMENTS.includes(line.type)
    })
  } else {
    // selection not applicable - does this line alone support commenting?
    return !isEmptyDiffLine(diffLine) && LINE_TYPES_SUPPORTING_COMMENTS.includes(diffLine.type)
  }
}

/**
 * Returns the text content from the given diffLines as a single string
 */
export const getContentFromLines = (lines?: ClientDiffLine[]): string => {
  if (!lines) return ''
  const content = lines
    .filter((line): line is DiffLine => !isEmptyDiffLine(line))
    .map(line => {
      const parsedContent = parseHtml(line.html)
      const [trimmedContent] = trimContentLine(parsedContent, line.type)
      return trimmedContent
    })

  return content.join('\n')
}

/**
 * Determines if a diff line requires additional padding to accommodate markers.
 *
 * This function checks two specific cases where markers would otherwise
 * overlap with line content:
 *
 * 1. Empty context lines (length 0) that still need space for markers
 * 2. Addition/deletion lines that contain only a single character (+ or -),
 *    which would otherwise have markers overlap with this syntax character
 *
 * @param line - The diff line to evaluate
 * @returns true if the line needs additional padding for markers, false otherwise
 */
export function lineNeedsMarkerPadding(line: DiffLine): boolean {
  if (line.text.length < 1 && (line.type === 'CONTEXT' || line.type === 'INJECTED_CONTEXT')) {
    return true
  }

  if (
    (line.type === 'DELETION' || line.type === 'ADDITION') &&
    line.text.length === 1 &&
    ['+', '-'].includes(line.text.charAt(0))
  ) {
    return true
  }

  return false
}

/**
 * Extracts the selected line range from the given diffLine. If the selectedDiffRowRange is undefined, it will
 * return a fallback selected diff line range based on the given diffLine and isLeftSide.
 * This lets a user chat about a single line of code without having to select the line number explicitly.
 * An undefined selectedDiffRowRange typically occurs when chat is intitated from the context menu without selecting a line.
 * @param selectedDiffRowRange The selected diff line range
 * @param diffLine The diff line that triggered the context menu
 * @param isLeftSide Whether the diff line is on the left side
 * @param fileAnchor The file anchor for the diff line
 * @returns The selected diff line range or undefined if no range is found
 */
export const copilotSelectedDiffLineRange = (
  selectedDiffRowRange: LineRange | undefined,
  diffLine: ClientDiffLine,
  isLeftSide: boolean | undefined,
  fileAnchor: DiffAnchor,
): LineRange | undefined => {
  let fallbackSelectedRange: LineRange | undefined = undefined

  if (selectedDiffRowRange) {
    return selectedDiffRowRange
  }

  if (!isEmptyDiffLine(diffLine)) {
    const lineNumber = (isLeftSide ? diffLine.left : diffLine.right) ?? 0
    const orientation = isLeftSide ? 'left' : 'right'

    fallbackSelectedRange = {
      startOrientation: orientation,
      endOrientation: orientation,
      startLineNumber: lineNumber,
      endLineNumber: lineNumber,
      firstSelectedLineNumber: lineNumber,
      firstSelectedOrientation: orientation,
      diffAnchor: fileAnchor,
    }
  }

  return fallbackSelectedRange
}

/**
 * Determines the appropriate background color CSS variable for a diff line based on its type and state.
 *
 * This function returns CSS variables that correspond to different visual appearances in the diff UI.
 * The color varies based on:
 * - The type of diff line (addition, deletion, hunk, empty, or context)
 * - Whether it's a line number cell or content cell
 * - Whether the line is currently selected
 *
 * @param lineType - The type of diff line (ADDITION, DELETION, HUNK, EMPTY, etc.)
 * @param isNumberCellOrActiveMarkersDialog - Whether this is for a line number cell (true), active markers dialog (true) or line content cell (false)
 * @param isRowSelected - Whether the line is currently selected by the user
 * @returns A CSS variable string representing the appropriate background color, or undefined
 */
export function getLineBackgroundColor(
  lineType: DiffLineType,
  isNumberCellOrActiveMarkersDialog = false,
  isRowSelected = false,
): string {
  let primaryColor: string

  switch (lineType) {
    case 'ADDITION':
      primaryColor = isNumberCellOrActiveMarkersDialog
        ? 'var(--diffBlob-additionNum-bgColor, var(--diffBlob-addition-bgColor-num))'
        : 'var(--diffBlob-additionLine-bgColor, var(--diffBlob-addition-bgColor-line))'
      break
    case 'DELETION':
      primaryColor = isNumberCellOrActiveMarkersDialog
        ? 'var(--diffBlob-deletionNum-bgColor, var(--diffBlob-deletion-bgColor-num))'
        : 'var(--diffBlob-deletionLine-bgColor, var(--diffBlob-deletion-bgColor-line))'
      break
    case 'HUNK':
      primaryColor = isNumberCellOrActiveMarkersDialog
        ? 'var(--diffBlob-hunkNum-bgColor-rest, var(--diffBlob-hunk-bgColor-num))'
        : 'var(--diffBlob-hunkLine-bgColor, var(--bgColor-accent-muted))'
      break
    case 'EMPTY':
      primaryColor = isNumberCellOrActiveMarkersDialog
        ? 'var(--diffBlob-emptyNum-bgColor, var(--diffBlob-hunk-bgColor-num))'
        : 'var(--diffBlob-emptyLine-bgColor, var(--bgColor-accent-muted))'
      break
    default:
      primaryColor = 'var(--bgColor-default)'
  }

  if (!isRowSelected) return primaryColor

  return `color-mix(in oklab, var(--bgColor-accent-emphasis) 8%, ${primaryColor})`
}
