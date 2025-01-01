import type {DiffLine, DiffLineType} from '@github-ui/diffs/types'
import type {Change, ParsedDiff} from 'diff'
import {diffWordsWithSpace} from 'diff'

import type {ChangedFile} from './workspace-editor-types'

const COLORIZED_LINE_LENGTH_LIMIT = 1024

const lineTypeMap: {[key: string]: DiffLineType} = {
  '+': 'ADDITION',
  '-': 'DELETION',
  ' ': 'CONTEXT',
}

interface ApiDiffLine {
  text: string
  current: number
  type: DiffLineType
}

interface ApiDiff {
  old_path?: string
  new_path?: string
  status: 'A' | 'D' | 'M' | 'R' | undefined
  lines: ApiDiffLine[]
}

/**
 * Map a client diff to a server diff.
 */
export function mapChangedFileToServerDiff(file: ChangedFile): ApiDiff {
  const patch = file.patch
  const lines = patch.hunks.flatMap(hunk => {
    const hunkLines: ApiDiffLine[] = []
    let currentOriginalLineNumber = hunk.oldStart
    let currentModifiedLineNumber = hunk.newStart

    for (let i = 0; i < hunk.lines.length; i++) {
      const line = hunk.lines[i]!
      const type = lineTypeMap[line.charAt(0)]
      if (!type) continue
      if (type === 'CONTEXT') {
        currentOriginalLineNumber++
        currentModifiedLineNumber++
        continue
      }

      hunkLines.push({
        text: line,
        current: type === 'ADDITION' ? currentModifiedLineNumber : currentOriginalLineNumber,
        type,
      })

      if (type === 'DELETION') currentOriginalLineNumber++
      if (type === 'ADDITION') currentModifiedLineNumber++
    }

    return hunkLines
  })

  return {lines, new_path: patch.newFileName, old_path: patch.oldFileName, status: file.status}
}

export function mapPatchToDiffLines(patch: ParsedDiff): DiffLine[] {
  return patch.hunks.flatMap(hunk => {
    let deleteLines: DiffLine[] = []
    let addLines: DiffLine[] = []
    const hunkLines: DiffLine[] = []
    let currentOriginalLineNumber = hunk.oldStart
    let currentModifiedLineNumber = hunk.newStart

    for (let i = 0; i < hunk.lines.length; i++) {
      const line = hunk.lines[i]!
      const type = lineTypeMap[line.charAt(0)]
      if (!type) continue

      const text = line.slice(1)
      const hunkLine: DiffLine = {
        left: currentOriginalLineNumber,
        html: escapeHTML(text),
        right: currentModifiedLineNumber,
        text,
        type,
      }

      if (type === 'DELETION') {
        currentOriginalLineNumber++
        deleteLines.push(hunkLine)
      } else if (type === 'ADDITION') {
        currentModifiedLineNumber++
        addLines.push(hunkLine)
      } else if (type === 'CONTEXT') {
        // If we're back into context after getting through deletions and
        // additions, we can highlight the tokens and add them to hunkLines
        ;[deleteLines, addLines] = highlightLineChanges(deleteLines, addLines)
        hunkLines.push(...deleteLines)
        deleteLines = []
        hunkLines.push(...addLines)
        addLines = []
        currentOriginalLineNumber++
        currentModifiedLineNumber++
        hunkLines.push(hunkLine)
      }
    }

    if (addLines.length > 0 || deleteLines.length > 0) {
      ;[deleteLines, addLines] = highlightLineChanges(deleteLines, addLines)
      hunkLines.push(...deleteLines)
      deleteLines = []
      hunkLines.push(...addLines)
      addLines = []
    }

    return hunkLines
  })
}

function highlightLineChanges(deleteLines: DiffLine[], addLines: DiffLine[]): [DiffLine[], DiffLine[]] {
  // Only highlight tokens if the number of lines deleted/added is the same
  if (addLines.length !== deleteLines.length) {
    return [deleteLines, addLines]
  }

  if (addLines.some((line: DiffLine) => line.text.length > COLORIZED_LINE_LENGTH_LIMIT)) {
    return [deleteLines, addLines]
  }

  if (deleteLines.some((line: DiffLine) => line.text.length > COLORIZED_LINE_LENGTH_LIMIT)) {
    return [deleteLines, addLines]
  }

  for (let idx = 0; idx < deleteLines.length; idx++) {
    const diffParts = diffWordsWithSpace(deleteLines[idx]!.text, addLines[idx]!.text)

    let deletedLines = diffParts.filter(part => part.removed || !part.added)
    let addedLines = diffParts.filter(part => part.added || !part.removed)

    deletedLines = combineRelatedTokens(deletedLines)
    addedLines = combineRelatedTokens(addedLines)

    deleteLines[idx]!.html = tokenToHtml(deletedLines)
    addLines[idx]!.html = tokenToHtml(addedLines)
  }

  return [deleteLines, addLines]
}

/**
 * Combine neighboring words with changes.
 * Note that this does not distinguish between added and removed words, so it
 * is up to the user to prepare the inputs to they are only one type of change.
 */
export function combineRelatedTokens(diffParts: Change[]): Change[] {
  const outputChanges = []
  for (let j = 0; j < diffParts.length; j++) {
    const part = diffParts[j]!
    const isNextPartAChange = diffParts[j + 1]?.added || diffParts[j + 1]?.removed

    if (part.added || part.removed) {
      const previousPart = outputChanges[outputChanges.length - 1]
      if (previousPart && (previousPart.added || previousPart.removed)) {
        outputChanges[outputChanges.length - 1]!.value += part.value
      } else {
        outputChanges.push(part)
      }
    } else if (isNextPartAChange && part.value.match(/^\s+$/)) {
      if (outputChanges[outputChanges.length - 1]) {
        outputChanges[outputChanges.length - 1]!.value += part.value
      } else {
        outputChanges.push(part)
      }
    } else {
      outputChanges.push(part)
    }
  }

  return outputChanges
}

function tokenToHtml(changes: Change[]): string {
  const output = []

  for (const part of changes) {
    if (part.added || part.removed) {
      const span = document.createElement('span')
      // don't escape the HTML, the browser will do that for us
      span.textContent = part.value
      span.classList.add('x', 'x-first', 'x-last')
      output.push(span.outerHTML)
    } else {
      output.push(escapeHTML(part.value))
    }
  }

  return output.join('')
}

/**
 * 1. No, there is no standard library solution for this
 * 2. Yes, this is actually the fastest way; the switch statement is slightly
 *    faster than a object lookup or map, and in aggregate, that adds up.
 */
function escapeHTML(unsafe: string): string {
  return unsafe.replace(/[&<>"']/g, escapeHTMLChar)
}

function escapeHTMLChar(char: string): string {
  switch (char) {
    case '&':
      return '&amp;'
    case '<':
      return '&lt;'
    case '>':
      return '&gt;'
    case '"':
      return '&quot;'
    case "'":
      return '&#039;'
    default:
      return char
  }
}
