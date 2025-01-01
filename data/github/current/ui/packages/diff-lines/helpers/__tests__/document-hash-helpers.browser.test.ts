import {
  isSelectingDiffLineOrRange,
  parseLineRangeHash,
  parsePathDigestWithoutLineNumbers,
} from '../document-hash-helpers'
import {describe, expect, it} from '@github-ui/tests'

describe('isSelectingDiffLineOrRange', () => {
  /*
   * Invalid cases
   */
  it('returns false for invalid hash', () => {
    const invalidHash = 'not-valid'
    const isSelecting = isSelectingDiffLineOrRange(invalidHash)
    expect(isSelecting).toBe(false)
  })

  it('returns false for invalid hash with left line number', () => {
    const invalidHash = 'not-validL8'
    const isSelecting = isSelectingDiffLineOrRange(invalidHash)
    expect(isSelecting).toBe(false)
  })

  it('returns false for invalid hash with right line number', () => {
    const invalidHash = 'not-validR1'
    const isSelecting = isSelectingDiffLineOrRange(invalidHash)
    expect(isSelecting).toBe(false)
  })

  it('returns false for invalid hash with range', () => {
    const invalidHash = 'not-validR1-L8'
    const isSelecting = isSelectingDiffLineOrRange(invalidHash)
    expect(isSelecting).toBe(false)
  })

  /*
   * No line number or range cases
   */
  it('returns false for valid hash with prefix, "#" symbol, and no line number', () => {
    const hashWithoutLineNumbers = '#diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a'
    const isSelecting = isSelectingDiffLineOrRange(hashWithoutLineNumbers)
    expect(isSelecting).toBe(false)
  })

  it('returns false for valid hash with prefix, no "#" symbol, and no line number', () => {
    const hashWithoutLineNumbers = 'diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a'
    const isSelecting = isSelectingDiffLineOrRange(hashWithoutLineNumbers)
    expect(isSelecting).toBe(false)
  })

  it('returns false for valid hash with no prefix, no "#" symbol, and no line number', () => {
    const hashWithoutLineNumbers = '8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a'
    const isSelecting = isSelectingDiffLineOrRange(hashWithoutLineNumbers)
    expect(isSelecting).toBe(false)
  })

  /*
   * Line number cases
   */
  it('returns true for valid hash with no prefix and left line number', () => {
    const validHash = '8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aL8'
    const isSelecting = isSelectingDiffLineOrRange(validHash)
    expect(isSelecting).toBe(true)
  })

  it('returns true for valid hash with no prefix and right line number', () => {
    const validHash = '8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aR1'
    const isSelecting = isSelectingDiffLineOrRange(validHash)
    expect(isSelecting).toBe(true)
  })

  it('returns true for valid hash with prefix and left line number', () => {
    const validHash = 'diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aL8'
    const isSelecting = isSelectingDiffLineOrRange(validHash)
    expect(isSelecting).toBe(true)
  })

  it('returns true for valid hash with prefix and right line number', () => {
    const validHash = 'diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aR1'
    const isSelecting = isSelectingDiffLineOrRange(validHash)
    expect(isSelecting).toBe(true)
  })

  it('returns true for valid hash with "#" symbol, prefix and left line number', () => {
    const validHash = '#diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aL8'
    const isSelecting = isSelectingDiffLineOrRange(validHash)
    expect(isSelecting).toBe(true)
  })

  it('returns true for valid hash with "#" symbol, prefix and right line number', () => {
    const validHash = '#diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aR1'
    const isSelecting = isSelectingDiffLineOrRange(validHash)
    expect(isSelecting).toBe(true)
  })

  /*
   * Line range cases
   */
  it('returns true for valid hash with no prefix and range', () => {
    const validHash = '8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aR1-L8'
    const isSelecting = isSelectingDiffLineOrRange(validHash)
    expect(isSelecting).toBe(true)
  })

  it('returns true for valid hash with prefix and range', () => {
    const validHash = 'diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aR1-L8'
    const isSelecting = isSelectingDiffLineOrRange(validHash)
    expect(isSelecting).toBe(true)
  })

  it('returns true for valid hash with "#" symbol, prefix and range', () => {
    const validHash = '#diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aR1-L8'
    const isSelecting = isSelectingDiffLineOrRange(validHash)
    expect(isSelecting).toBe(true)
  })
})

describe('parsePathDigestWithoutLineNumbers', () => {
  it('parses and returns no data for invalid hash', () => {
    const invalidHash = 'not-valid'
    const pathDigest = parsePathDigestWithoutLineNumbers(invalidHash)
    expect(pathDigest).toBe(undefined)
  })

  /*
   * Path digest only cases
   */
  it('parses and returns data for valid hash with no prefix, no line numbers, no line range', () => {
    const validHash = '8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a'
    const pathDigest = parsePathDigestWithoutLineNumbers(validHash)
    expect(pathDigest).toBe('8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a')
  })

  it('parses and returns data for valid hash with prefix', () => {
    const validHash = 'diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a'
    const pathDigest = parsePathDigestWithoutLineNumbers(validHash)
    expect(pathDigest).toBe('8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a')
  })

  it('parses and returns data for valid hash with "#" symbol and prefix', () => {
    const validHash = '#diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a'
    const pathDigest = parsePathDigestWithoutLineNumbers(validHash)
    expect(pathDigest).toBe('8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a')
  })

  /*
   * Line number cases
   */
  it('parses and returns data for valid hash with no prefix and left line number', () => {
    const validHash = '8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aL8'
    const pathDigest = parsePathDigestWithoutLineNumbers(validHash)
    expect(pathDigest).toBe('8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a')
  })

  it('parses and returns data for valid hash with no prefix and right line number', () => {
    const validHash = '8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aR1'
    const pathDigest = parsePathDigestWithoutLineNumbers(validHash)
    expect(pathDigest).toBe('8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a')
  })

  it('parses and returns data for valid hash with prefix and left line number', () => {
    const validHash = 'diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aL8'
    const pathDigest = parsePathDigestWithoutLineNumbers(validHash)
    expect(pathDigest).toBe('8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a')
  })

  it('parses and returns data for valid hash with prefix and right line number', () => {
    const validHash = 'diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aR1'
    const pathDigest = parsePathDigestWithoutLineNumbers(validHash)
    expect(pathDigest).toBe('8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a')
  })

  it('parses and returns data for valid hash with "#" symbol, prefix and left line number', () => {
    const validHash = '#diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aL8'
    const pathDigest = parsePathDigestWithoutLineNumbers(validHash)
    expect(pathDigest).toBe('8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a')
  })

  it('parses and returns data for valid hash with "#" symbol, prefix and right line number', () => {
    const validHash = '#diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aR1'
    const pathDigest = parsePathDigestWithoutLineNumbers(validHash)
    expect(pathDigest).toBe('8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a')
  })

  /*
   * Line range cases
   */
  it('parses and returns data for valid hash with no prefix and range', () => {
    const validHash = '8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aR1-L8'
    const pathDigest = parsePathDigestWithoutLineNumbers(validHash)
    expect(pathDigest).toBe('8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a')
  })

  it('parses and returns data for valid hash with prefix and range', () => {
    const validHash = 'diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aR1-L8'
    const pathDigest = parsePathDigestWithoutLineNumbers(validHash)
    expect(pathDigest).toBe('8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a')
  })

  it('parses and returns data for valid hash with "#" symbol, prefix and range', () => {
    const validHash = '#diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aR1-L8'
    const pathDigest = parsePathDigestWithoutLineNumbers(validHash)
    expect(pathDigest).toBe('8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a')
  })
})

describe('parseLineRangeHash', () => {
  it('parses and returns data for valid hash', () => {
    const validHash = 'diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aR1'
    const lineRange = parseLineRangeHash(validHash)
    expect(lineRange?.diffAnchor).toBe('diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a')
    expect(lineRange?.startOrientation).toBe('right')
    expect(lineRange?.startLineNumber).toBe(1)
  })

  it('parses and returns no data for invalid hash', () => {
    const invalidHash = 'not-valid'
    const lineRange = parseLineRangeHash(invalidHash)
    expect(lineRange?.diffAnchor).toBe(undefined)
    expect(lineRange?.startOrientation).toBe(undefined)
    expect(lineRange?.startLineNumber).toBe(undefined)
  })

  it('parses and returns data for valid hash with range', () => {
    const validHash = 'diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84aR1-L8'
    const lineRange = parseLineRangeHash(validHash)
    expect(lineRange?.diffAnchor).toBe('diff-8814ae58da61ecd055d589e3dc7b3d51c9304bbf87e2a76bcc92d345c955e84a')
    expect(lineRange?.startOrientation).toBe('right')
    expect(lineRange?.startLineNumber).toBe(1)
    expect(lineRange?.endOrientation).toBe('left')
    expect(lineRange?.endLineNumber).toBe(8)
  })
})
