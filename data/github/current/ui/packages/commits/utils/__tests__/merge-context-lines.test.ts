import {mergeContextLines} from '../merge-context-lines'

const defaultProps = {
  blobLineNumber: 1,
  displayNoNewLineWarning: false,
  type: 'ADDITION' as const,
  html: '',
  text: '',
  threadsData: undefined,
}

const INITIAL_POSITION = 99

describe('mergeContextLines', () => {
  it('should merge context lines correctly when merging from above', () => {
    const initialDiffLines = [{left: 3, right: 3, position: INITIAL_POSITION, ...defaultProps}]
    const expandedDiffLines = [
      {left: 1, right: 1, position: 1, ...defaultProps},
      {left: 2, right: 2, position: 2, ...defaultProps},
      {left: 3, right: 3, position: 3, ...defaultProps},
    ]

    const result = mergeContextLines(initialDiffLines, expandedDiffLines)

    expect(result).toEqual([
      {left: 1, right: 1, position: null, ...defaultProps},
      {left: 2, right: 2, position: null, ...defaultProps},
      {left: 3, right: 3, position: INITIAL_POSITION, ...defaultProps},
    ])
  })

  it('should merge context lines correctly when merging from below', () => {
    const initialDiffLines = [{left: 1, right: 1, position: INITIAL_POSITION, ...defaultProps}]
    const expandedDiffLines = [
      {left: 1, right: 1, position: 1, ...defaultProps},
      {left: 2, right: 2, position: 2, ...defaultProps},
      {left: 3, right: 3, position: 3, ...defaultProps},
    ]

    const result = mergeContextLines(initialDiffLines, expandedDiffLines)

    expect(result).toEqual([
      {left: 1, right: 1, position: INITIAL_POSITION, ...defaultProps},
      {left: 2, right: 2, position: null, ...defaultProps},
      {left: 3, right: 3, position: null, ...defaultProps},
    ])
  })

  it('should merge context lines correctly when merging in between', () => {
    const INITIAL_POSITION_1 = 100
    const INITIAL_POSITION_2 = 200

    const initialDiffLines = [
      {left: 1, right: 1, position: INITIAL_POSITION_1, ...defaultProps},
      {left: 3, right: 3, position: INITIAL_POSITION_2, ...defaultProps},
    ]
    const expandedDiffLines = [
      {left: 1, right: 1, position: 1, ...defaultProps},
      {left: 2, right: 2, position: 2, ...defaultProps},
      {left: 3, right: 3, position: 3, ...defaultProps},
    ]

    const result = mergeContextLines(initialDiffLines, expandedDiffLines)

    expect(result).toEqual([
      {left: 1, right: 1, position: INITIAL_POSITION_1, ...defaultProps},
      {left: 2, right: 2, position: null, ...defaultProps},
      {left: 3, right: 3, position: INITIAL_POSITION_2, ...defaultProps},
    ])
  })

  it('should merge context lines correctly when expanding all lines', () => {
    const INITIAL_POSITION_1 = 100
    const INITIAL_POSITION_2 = 200

    const initialDiffLines = [
      {left: 2, right: 2, position: INITIAL_POSITION_1, ...defaultProps},
      {left: 5, right: 5, position: INITIAL_POSITION_2, ...defaultProps},
    ]
    const expandedDiffLines = [
      {left: 1, right: 1, position: 1, ...defaultProps},
      {left: 2, right: 2, position: 2, ...defaultProps},
      {left: 3, right: 3, position: 3, ...defaultProps},
      {left: 4, right: 4, position: 4, ...defaultProps},
      {left: 5, right: 5, position: 5, ...defaultProps},
      {left: 6, right: 6, position: 6, ...defaultProps},
    ]

    const result = mergeContextLines(initialDiffLines, expandedDiffLines)

    expect(result).toEqual([
      {left: 1, right: 1, position: null, ...defaultProps},
      {left: 2, right: 2, position: INITIAL_POSITION_1, ...defaultProps},
      {left: 3, right: 3, position: null, ...defaultProps},
      {left: 4, right: 4, position: null, ...defaultProps},
      {left: 5, right: 5, position: INITIAL_POSITION_2, ...defaultProps},
      {left: 6, right: 6, position: null, ...defaultProps},
    ])
  })

  it('should handle empty initialDiffLines correctly', () => {
    const expandedDiffLines = [
      {left: 1, right: 1, position: null, ...defaultProps},
      {left: 2, right: 2, position: null, ...defaultProps},
    ]

    const result = mergeContextLines([], expandedDiffLines)

    expect(result).toEqual([
      {left: 1, right: 1, position: null, ...defaultProps},
      {left: 2, right: 2, position: null, ...defaultProps},
    ])
  })

  it('should handle empty expandedDiffLines correctly', () => {
    const initialDiffLines = [{left: 1, right: 1, position: 1, ...defaultProps}]

    const result = mergeContextLines(initialDiffLines, [])

    expect(result).toEqual([])
  })
})
