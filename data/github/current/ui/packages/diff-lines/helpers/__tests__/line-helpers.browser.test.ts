import type {DiffAnchor, DiffLineType} from '@github-ui/diffs/types'
import {isMacOS} from '@github-ui/get-os'
import {beforeEach, describe, it, expect, vi} from '@github-ui/tests'

import {buildDiffLine} from '../../test-utils/query-data'
import {
  anchorLinkForSelection,
  calculateDiffLineCodeCellGutter,
  copilotSelectedDiffLineRange,
  getLineBackgroundColor,
  getKeyboardShortcutString,
  lineNeedsMarkerPadding,
  orderLineRange,
} from '../line-helpers'
import {EMPTY_DIFF_LINE, type DiffLine, type LineRange} from '../../types'

vi.mock('@github-ui/get-os')
const mockedIsMacOS = vi.mocked(isMacOS)

it('Out of order diff line range is correctly re-ordered', () => {
  const diffLine1: DiffLine = buildDiffLine({type: 'CONTEXT', blobLineNumber: 1, html: '', left: 1, right: 1})
  const diffLine2: DiffLine = buildDiffLine({type: 'CONTEXT', blobLineNumber: 2, html: '', left: 2, right: 2})
  const diffLines = [diffLine1, diffLine2]
  const lineRange: LineRange = {
    diffAnchor: 'diff',
    startOrientation: 'right',
    startLineNumber: 2,
    endOrientation: 'right',
    endLineNumber: 1,
    firstSelectedLineNumber: 2,
    firstSelectedOrientation: 'right',
  }

  const reorderedRange = orderLineRange(lineRange, diffLines)
  expect(reorderedRange?.startLineNumber).toBe(1)
  expect(reorderedRange?.endLineNumber).toBe(2)
  expect(reorderedRange?.firstSelectedLineNumber).toBe(2)
})

it('Correctly ordered diff line is returned unchanged', () => {
  const diffLine1: DiffLine = buildDiffLine({type: 'CONTEXT', blobLineNumber: 1, html: '', left: 1, right: 1})
  const diffLine2: DiffLine = buildDiffLine({type: 'CONTEXT', blobLineNumber: 2, html: '', left: 2, right: 2})
  const diffLines = [diffLine1, diffLine2]
  const lineRange: LineRange = {
    diffAnchor: 'diff',
    startOrientation: 'right',
    startLineNumber: 1,
    endOrientation: 'right',
    endLineNumber: 2,
    firstSelectedLineNumber: 1,
    firstSelectedOrientation: 'right',
  }

  const reorderedRange = orderLineRange(lineRange, diffLines)
  expect(reorderedRange?.startLineNumber).toBe(1)
  expect(reorderedRange?.endLineNumber).toBe(2)
  expect(reorderedRange?.firstSelectedLineNumber).toBe(1)
})

describe('anchorLinkForSelection', () => {
  it('returns the link to a range when one is given', () => {
    const range: LineRange = {
      diffAnchor: 'diff-anchor',
      endLineNumber: 5,
      endOrientation: 'right',
      startLineNumber: 1,
      startOrientation: 'left',
      firstSelectedOrientation: 'left',
      firstSelectedLineNumber: 1,
    }

    const result = anchorLinkForSelection({range, fileAnchor: range.diffAnchor as DiffAnchor})

    expect(result).toContain('#diff-anchorL1-R5')
  })

  it('returns the link to a line when given a file and line but no range', () => {
    const diffLine = buildDiffLine({left: 1, right: 2, type: 'ADDITION'})

    const result = anchorLinkForSelection({line: diffLine, fileAnchor: 'diff-anchor' as DiffAnchor})

    expect(result).toContain('#diff-anchorR2')
  })

  it('returns empty string if a file anchor is given without a line', () => {
    const result = anchorLinkForSelection({fileAnchor: 'diff-anchor' as DiffAnchor})

    expect(result).not.toBeDefined()
  })
})

describe('getKeyboardShortcutString for Mac', () => {
  beforeEach(() => {
    mockedIsMacOS.mockReturnValue(true)
  })
  it('Keyboard shortcut includes Control key by default', () => {
    const shortcutString = getKeyboardShortcutString({key: 'A'})
    const expectedString = '⌘A'

    expect(shortcutString).toBe(expectedString)

    const shortcutStringNoControl = getKeyboardShortcutString({key: 'A', includeControlKey: false})
    const expectedStringNoControl = 'A'
    expect(shortcutStringNoControl).toBe(expectedStringNoControl)
  })

  it('Keyboard shortcut with Shift key is generated correctly', () => {
    const shortcutString = getKeyboardShortcutString({key: 'A', includeShiftKey: true})
    const expectedString = '⌘⇧A'

    expect(shortcutString).toBe(expectedString)
  })

  it('Keyboard shortcut with Option key is generated correctly', () => {
    const shortcutString = getKeyboardShortcutString({key: 'A', includeOptionKey: true})
    const expectedString = '⌘⌥A'

    expect(shortcutString).toBe(expectedString)
  })
})

describe('getKeyboardShortcutString for Windows', () => {
  beforeEach(() => {
    mockedIsMacOS.mockReturnValue(false)
  })

  it('Keyboard shortcut includes Control key by default', () => {
    const shortcutString = getKeyboardShortcutString({key: 'A'})
    const expectedString = 'Ctrl + A'

    expect(shortcutString).toBe(expectedString)

    const shortcutStringNoControl = getKeyboardShortcutString({key: 'A', includeControlKey: false})
    const expectedStringNoControl = 'A'
    expect(shortcutStringNoControl).toBe(expectedStringNoControl)
  })

  it('Keyboard shortcut with Shift key is generated correctly', () => {
    const shortcutString = getKeyboardShortcutString({key: 'A', includeShiftKey: true})
    const expectedString = 'Ctrl + Shift + A'

    expect(shortcutString).toBe(expectedString)
  })

  it('Keyboard shortcut with Option key is generated correctly', () => {
    const shortcutString = getKeyboardShortcutString({key: 'A', includeOptionKey: true})
    const expectedString = 'Ctrl + Alt + A'

    expect(shortcutString).toBe(expectedString)
  })
})

describe('calculateDiffLineCodeCellGutter', () => {
  it('when hasThreads is false, it returns 30px', () => {
    expect(calculateDiffLineCodeCellGutter({hasThreads: false})).toEqual('24px')
  })

  it('when hasThreads is true, it returns 96px', () => {
    expect(calculateDiffLineCodeCellGutter({hasThreads: true})).toEqual('80px')
  })
})

describe('lineNeedsMarkerPadding', () => {
  describe('when CONTEXT line', () => {
    it('returns true if empty', () => {
      const diffLine: DiffLine = buildDiffLine({type: 'CONTEXT', text: ''})
      expect(lineNeedsMarkerPadding(diffLine)).toBe(true)
    })

    it('returns false if content is present', () => {
      const diffLine: DiffLine = buildDiffLine({type: 'CONTEXT', text: 'content here'})
      expect(lineNeedsMarkerPadding(diffLine)).toBe(false)
    })
  })

  describe('when INJECTED_CONTEXT line', () => {
    it('returns true if empty', () => {
      const diffLine: DiffLine = buildDiffLine({type: 'INJECTED_CONTEXT', text: ''})
      expect(lineNeedsMarkerPadding(diffLine)).toBe(true)
    })

    it('returns false if content is present', () => {
      const diffLine: DiffLine = buildDiffLine({type: 'INJECTED_CONTEXT', text: 'content here'})
      expect(lineNeedsMarkerPadding(diffLine)).toBe(false)
    })
  })

  describe('when ADDITION line', () => {
    it('returns true if empty', () => {
      const diffLine: DiffLine = buildDiffLine({type: 'ADDITION', text: '+'})
      expect(lineNeedsMarkerPadding(diffLine)).toBe(true)
    })

    it('returns false if content is present', () => {
      const diffLine: DiffLine = buildDiffLine({type: 'ADDITION', text: '+add content'})
      expect(lineNeedsMarkerPadding(diffLine)).toBe(false)
    })
  })

  describe('when DELETION line', () => {
    it('returns true if empty', () => {
      const diffLine: DiffLine = buildDiffLine({type: 'DELETION', text: '-'})
      expect(lineNeedsMarkerPadding(diffLine)).toBe(true)
    })

    it('returns false if content is present', () => {
      const diffLine: DiffLine = buildDiffLine({type: 'DELETION', text: '-deleted content'})
      expect(lineNeedsMarkerPadding(diffLine)).toBe(false)
    })
  })
})

describe('copilotSelectedDiffLineRange', () => {
  const fileAnchor = 'diff-file-anchor'

  it('returns selectedDiffRowRange when selectedDiffRowRange is provided', () => {
    const selectedDiffRowRange = {
      startOrientation: 'left' as const,
      endOrientation: 'left' as const,
      startLineNumber: 1,
      endLineNumber: 1,
      firstSelectedLineNumber: 1,
      firstSelectedOrientation: 'left' as const,
      diffAnchor: fileAnchor,
    }

    const diffLine = buildDiffLine({left: 1, right: 1, type: 'ADDITION'})

    const result = copilotSelectedDiffLineRange(selectedDiffRowRange, diffLine, true, fileAnchor)

    expect(result).toEqual(selectedDiffRowRange)
  })

  it('returns undefined when diffLine is EMPTY_DIFF_LINE', () => {
    const result = copilotSelectedDiffLineRange(undefined, EMPTY_DIFF_LINE, true, fileAnchor)

    expect(result).toBeUndefined()
  })

  it('returns a range with left orientation when isLeftSide is true', () => {
    const diffLine = buildDiffLine({left: 10, right: 15, type: 'ADDITION'})

    const result = copilotSelectedDiffLineRange(undefined, diffLine, true, fileAnchor)

    expect(result).toEqual({
      startOrientation: 'left',
      endOrientation: 'left',
      startLineNumber: 10,
      endLineNumber: 10,
      firstSelectedLineNumber: 10,
      firstSelectedOrientation: 'left',
      diffAnchor: fileAnchor,
    })
  })

  it('returns a range with right orientation when isLeftSide is false', () => {
    const diffLine = buildDiffLine({left: 10, right: 15, type: 'ADDITION'})

    const result = copilotSelectedDiffLineRange(undefined, diffLine, false, fileAnchor)

    expect(result).toEqual({
      startOrientation: 'right',
      endOrientation: 'right',
      startLineNumber: 15,
      endLineNumber: 15,
      firstSelectedLineNumber: 15,
      firstSelectedOrientation: 'right',
      diffAnchor: fileAnchor,
    })
  })
})

describe('getLineBackgroundColor', () => {
  it('returns correct color for addition line', () => {
    // Test line content cells
    expect(getLineBackgroundColor('ADDITION')).toBe(
      'var(--diffBlob-additionLine-bgColor, var(--diffBlob-addition-bgColor-line))',
    )

    // Test line number cell or active markers dialog
    expect(getLineBackgroundColor('ADDITION', true)).toBe(
      'var(--diffBlob-additionNum-bgColor, var(--diffBlob-addition-bgColor-num))',
    )

    // Test selected state
    expect(getLineBackgroundColor('ADDITION', false, true)).toBe(
      'color-mix(in oklab, var(--bgColor-accent-emphasis) 8%, var(--diffBlob-additionLine-bgColor, var(--diffBlob-addition-bgColor-line)))',
    )
  })

  it('returns correct color for deletion line', () => {
    // Test line content cells
    expect(getLineBackgroundColor('DELETION')).toBe(
      'var(--diffBlob-deletionLine-bgColor, var(--diffBlob-deletion-bgColor-line))',
    )

    // Test line number cell or active markers dialog
    expect(getLineBackgroundColor('DELETION', true)).toBe(
      'var(--diffBlob-deletionNum-bgColor, var(--diffBlob-deletion-bgColor-num))',
    )

    // Test selected state
    expect(getLineBackgroundColor('DELETION', true, true)).toBe(
      'color-mix(in oklab, var(--bgColor-accent-emphasis) 8%, var(--diffBlob-deletionNum-bgColor, var(--diffBlob-deletion-bgColor-num)))',
    )
  })

  it('returns correct color for hunk line', () => {
    // Test line content cells
    expect(getLineBackgroundColor('HUNK')).toBe('var(--diffBlob-hunkLine-bgColor, var(--bgColor-accent-muted))')

    // Test line number cell or active markers dialog
    expect(getLineBackgroundColor('HUNK', true)).toBe(
      'var(--diffBlob-hunkNum-bgColor-rest, var(--diffBlob-hunk-bgColor-num))',
    )

    // Test selected state
    expect(getLineBackgroundColor('HUNK', false, true)).toBe(
      'color-mix(in oklab, var(--bgColor-accent-emphasis) 8%, var(--diffBlob-hunkLine-bgColor, var(--bgColor-accent-muted)))',
    )
  })

  it('returns correct color for empty line', () => {
    // Test line content cells
    expect(getLineBackgroundColor('EMPTY')).toBe('var(--diffBlob-emptyLine-bgColor, var(--bgColor-accent-muted))')

    // Test line number cell or active markers dialog
    expect(getLineBackgroundColor('EMPTY', true)).toBe(
      'var(--diffBlob-emptyNum-bgColor, var(--diffBlob-hunk-bgColor-num))',
    )

    // Test selected state
    expect(getLineBackgroundColor('EMPTY', true, true)).toBe(
      'color-mix(in oklab, var(--bgColor-accent-emphasis) 8%, var(--diffBlob-emptyNum-bgColor, var(--diffBlob-hunk-bgColor-num)))',
    )
  })

  it('returns default color for context and other line types', () => {
    const lineTypes: DiffLineType[] = ['CONTEXT', 'INJECTED_CONTEXT']

    for (const lineType of lineTypes) {
      // Test default state
      expect(getLineBackgroundColor(lineType)).toBe('var(--bgColor-default)')

      // Test selected state
      expect(getLineBackgroundColor(lineType, false, true)).toBe(
        'color-mix(in oklab, var(--bgColor-accent-emphasis) 8%, var(--bgColor-default))',
      )
    }
  })

  it('handles all parameter combinations', () => {
    // Create a test matrix of all combinations
    const lineTypes: DiffLineType[] = ['ADDITION', 'DELETION', 'HUNK', 'EMPTY', 'CONTEXT', 'INJECTED_CONTEXT']
    const isNumberOptions = [true, false]
    const isSelectedOptions = [true, false]

    for (const lineType of lineTypes) {
      for (const isNumber of isNumberOptions) {
        for (const isSelected of isSelectedOptions) {
          // Just verify the function doesn't throw and returns a string
          const result = getLineBackgroundColor(lineType, isNumber, isSelected)
          expect(typeof result).toBe('string')
        }
      }
    }
  })
})
