import {diffLines} from 'diff'
import type {editor} from 'monaco-editor'

export type Operation = 'INSERTION' | 'DELETION' | 'EQUAL'
export type DiffLine = {
  operation: Operation
} & editor.IIdentifiedSingleEditOperation
export type EditorEdit = editor.IIdentifiedSingleEditOperation & {
  operation: Omit<Operation, 'EQUAL'>
}

export function getDiffLines(oldText: string, newText: string): DiffLine[] {
  // Compares two blocks of text while accounting for line endings
  const diffs = diffLines(oldText, newText, {newlineIsToken: true})

  // Track position in the document
  let currentLine = 1
  let currentColumn = 1

  return diffs.map((part, index) => {
    let operation: Operation = 'EQUAL'
    if (part.added) operation = 'INSERTION'
    if (part.removed) operation = 'DELETION'

    // Store the starting position before processing these lines
    const startLineNumber = currentLine
    const startColumn = currentColumn

    // Ensure endLineNumber and endColumn don't exceed oldText boundaries
    if (index === diffs.length - 1 && operation === 'INSERTION') {
      return {
        operation,
        text: part.value,
        range: {
          startLineNumber,
          startColumn,
          endLineNumber: currentLine,
          endColumn: currentColumn,
        },
      }
    }

    // Normalize Windows-style line endings to Unix-style first
    const normalizedValue = part.value.replace(/\r\n/g, '\n')

    // Process the text to find line breaks
    const lines = normalizedValue.split('\n')

    if (lines.length > 1) {
      // We have line breaks
      currentLine += lines.length - 1
      // Column position is determined by the last line's length
      currentColumn = lines[lines.length - 1]!.length + 1
    } else {
      // No line breaks, just advance the column
      currentColumn += part.value.length
    }

    return {
      operation,
      text: part.value,
      range: {
        startLineNumber,
        startColumn,
        endLineNumber: currentLine,
        endColumn: currentColumn,
      },
    }
  })
}

export function getEditorEdits(diffEdits: DiffLine[]): EditorEdit[] {
  const editsToApply: EditorEdit[] = []
  for (const edit of diffEdits) {
    const {operation, text, range} = edit
    switch (operation) {
      case 'INSERTION':
        editsToApply.push({
          range,
          text,
          forceMoveMarkers: true,
          operation,
        })
        break
      case 'DELETION':
        editsToApply.push({
          range,
          text: null,
          forceMoveMarkers: true,
          operation,
        })
        break
      case 'EQUAL':
      default:
        // no action needed if equal
        break
    }
  }
  return editsToApply
}
