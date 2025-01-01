import {mergeContextLines} from '../use-context-lines-data'
import type {DiffLine} from '@github-ui/diff-lines'

describe('mergeContextLines', () => {
  it('should merge expanded diff lines with initial diff lines, preserving position and no new line from initial lines', () => {
    const initialDiffLines = [
      {left: 1, right: 1, position: 10, text: 'line 1', displayNoNewLineWarning: true},
      {left: 2, right: 2, position: 20, text: 'line 2', displayNoNewLineWarning: false},
    ] as DiffLine[]

    const expandedDiffLines = [
      {left: 1, right: 1, text: 'line 1', displayNoNewLineWarning: false},
      {left: 2, right: 2, text: 'line 2', displayNoNewLineWarning: false},
      {left: 3, right: 3, text: 'line 3', displayNoNewLineWarning: false},
    ] as DiffLine[]

    const result = mergeContextLines(initialDiffLines, expandedDiffLines)

    expect(result).toEqual([
      {left: 1, right: 1, position: 10, text: 'line 1', displayNoNewLineWarning: true},
      {left: 2, right: 2, position: 20, text: 'line 2', displayNoNewLineWarning: false},
      {left: 3, right: 3, position: null, text: 'line 3', displayNoNewLineWarning: false, threadsData: undefined},
    ])
  })

  it('should handle cases where there are no initial diff lines', () => {
    const initialDiffLines: DiffLine[] = []

    const expandedDiffLines = [
      {left: 1, right: 1, text: 'line 1'},
      {left: 2, right: 2, text: 'line 2'},
    ] as DiffLine[]

    const result = mergeContextLines(initialDiffLines, expandedDiffLines)

    expect(result).toEqual([
      {left: 1, right: 1, position: null, text: 'line 1', threadsData: undefined},
      {left: 2, right: 2, position: null, text: 'line 2', threadsData: undefined},
    ])
  })

  it('should handle cases where there are no expanded diff lines', () => {
    const initialDiffLines = [
      {left: 1, right: 1, position: 10, text: 'line 1'},
      {left: 2, right: 2, position: 20, text: 'line 2'},
    ] as DiffLine[]

    const expandedDiffLines: DiffLine[] = []

    const result = mergeContextLines(initialDiffLines, expandedDiffLines)

    expect(result).toEqual([])
  })

  it('should handle cases where both initial and expanded diff lines are empty', () => {
    const initialDiffLines: DiffLine[] = []
    const expandedDiffLines: DiffLine[] = []

    const result = mergeContextLines(initialDiffLines, expandedDiffLines)

    expect(result).toEqual([])
  })

  it('should merge correctly when expanded lines partially overlap with initial lines', () => {
    const initialDiffLines = [
      {left: 1, right: 1, position: 10, text: 'line 1'},
      {left: 2, right: 2, position: 20, text: 'line 2'},
    ] as DiffLine[]

    const expandedDiffLines = [
      {left: 1, right: 1, position: 10, text: 'line 1'},
      {left: 2, right: 2, text: 'line 2 updated'},
      {left: 3, right: 3, text: 'line 3'},
    ] as DiffLine[]

    const result = mergeContextLines(initialDiffLines, expandedDiffLines)

    expect(result).toEqual([
      {left: 1, right: 1, position: 10, text: 'line 1'},
      {left: 2, right: 2, position: 20, text: 'line 2 updated'},
      {left: 3, right: 3, position: null, text: 'line 3', threadsData: undefined},
    ])
  })
})
