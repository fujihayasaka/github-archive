import {getDiffLines} from '../get-diff-lines'

describe('getDiffLines', () => {
  // Basic tests for simple string changes
  it('should detect an insertion at the end', () => {
    const oldText = 'Hello world'
    const newText = 'Hello world\nThis is on a new line!'

    const result = getDiffLines(oldText, newText)

    expect(result).toHaveLength(2)
    expect(result[0]).toMatchObject({
      operation: 'EQUAL',
      text: 'Hello world',
      range: {
        startLineNumber: 1,
        startColumn: 1,
        endLineNumber: 1,
        endColumn: 12,
      },
    })
    expect(result[1]).toMatchObject({
      operation: 'INSERTION',
      text: '\nThis is on a new line!',
      range: {
        startLineNumber: 1,
        startColumn: 12,
        endLineNumber: 1,
        endColumn: 12,
      },
    })
  })

  it('should detect a deletion at the beginning', () => {
    const oldText = 'Hello world\nThis is on a new line!'
    const newText = 'This is on a new line!'

    const result = getDiffLines(oldText, newText)

    expect(result).toHaveLength(2)
    expect(result[0]).toMatchObject({
      operation: 'DELETION',
      text: 'Hello world\n',
      range: {
        startLineNumber: 1,
        startColumn: 1,
        endLineNumber: 2,
        endColumn: 1,
      },
    })
    expect(result[1]).toMatchObject({
      operation: 'EQUAL',
      text: 'This is on a new line!',
      range: {
        startLineNumber: 2,
        startColumn: 1,
        endLineNumber: 2,
        endColumn: 23,
      },
    })
  })

  it('should handle replacement', () => {
    const oldText = 'Hello world'
    const newText = 'Hello there'

    const result = getDiffLines(oldText, newText)

    expect(result).toHaveLength(2)
    expect(result[0]).toMatchObject({
      operation: 'DELETION',
      text: 'Hello world',
      range: {
        startLineNumber: 1,
        startColumn: 1,
        endLineNumber: 1,
        endColumn: 12,
      },
    })
    expect(result[1]).toMatchObject({
      operation: 'INSERTION',
      text: 'Hello there',
      range: {
        startLineNumber: 1,
        startColumn: 12,
        endLineNumber: 1,
        endColumn: 12,
      },
    })
  })

  it('should handle no changes', () => {
    const text = 'Hello world'

    const result = getDiffLines(text, text)

    expect(result).toHaveLength(1)
    expect(result[0]).toMatchObject({
      operation: 'EQUAL',
      text: 'Hello world',
    })
  })

  // Line break tests
  it('should handle line breaks in insertion', () => {
    const oldText = 'Line 1\nLine 3'
    const newText = 'Line 1\nLine 2\nLine 3'

    const result = getDiffLines(oldText, newText)

    expect(result).toHaveLength(3)
    expect(result[0]).toMatchObject({
      operation: 'EQUAL',
      text: 'Line 1\n',
    })
    expect(result[1]).toMatchObject({
      operation: 'INSERTION',
      text: 'Line 2\n',
    })
    expect(result[2]).toMatchObject({
      operation: 'EQUAL',
      text: 'Line 3',
    })
  })

  it('should handle Windows-style line breaks', () => {
    const oldText = 'Line 1\r\nLine 2'
    const newText = 'Line 1\r\nModified line'

    const result = getDiffLines(oldText, newText)

    expect(result).toHaveLength(3)
    expect(result[0]).toMatchObject({
      operation: 'EQUAL',
      text: 'Line 1\r\n',
    })
    expect(result[1]).toMatchObject({
      operation: 'DELETION',
      text: 'Line 2',
    })
    expect(result[2]).toMatchObject({
      operation: 'INSERTION',
      text: 'Modified line',
    })
  })

  it('should calculate correct ranges for simple insertion', () => {
    const oldText = 'hello\nworld\nthis is new line'
    const newText = 'hello\nworld\nthis is new line\nand this is added'

    const result = getDiffLines(oldText, newText)

    expect(result).toHaveLength(2)
    expect(result[0]).toMatchObject({
      operation: 'EQUAL',
      text: 'hello\nworld\nthis is new line',
      range: {
        startLineNumber: 1,
        startColumn: 1,
        endLineNumber: 3,
        endColumn: 17,
      },
    })
    expect(result[1]).toMatchObject({
      operation: 'INSERTION',
      text: '\nand this is added',
      range: {
        startLineNumber: 3,
        startColumn: 17,
        endLineNumber: 3,
        endColumn: 17,
      },
    })
  })

  it('should calculate correct ranges for simple replace', () => {
    const oldText = 'hello\nworld\nthis is new line'
    const newText = 'hello\nworld\nfood\nlemon\nchocolate\nand this is added'

    const result = getDiffLines(oldText, newText)

    expect(result).toHaveLength(3)
    expect(result[0]).toMatchObject({
      operation: 'EQUAL',
      text: 'hello\nworld\n',
      range: {
        startLineNumber: 1,
        startColumn: 1,
        endLineNumber: 3,
        endColumn: 1,
      },
    })
    expect(result[1]).toMatchObject({
      operation: 'DELETION',
      text: 'this is new line',
      range: {
        startLineNumber: 3,
        startColumn: 1,
        endLineNumber: 3,
        endColumn: 17,
      },
    })
    expect(result[2]).toMatchObject({
      operation: 'INSERTION',
      text: 'food\nlemon\nchocolate\nand this is added',
      range: {
        startLineNumber: 3,
        startColumn: 17,
        endLineNumber: 3,
        endColumn: 17,
      },
    })
  })

  it('should handle empty strings', () => {
    const result1 = getDiffLines('', 'hello')
    expect(result1).toHaveLength(1)
    expect(result1[0]?.operation).toBe('INSERTION')

    const result2 = getDiffLines('hello', '')
    expect(result2).toHaveLength(1)
    expect(result2[0]?.operation).toBe('DELETION')
  })

  it('should handle completely different strings', () => {
    const result = getDiffLines('abc', 'xyz')
    expect(result).toHaveLength(2)
    expect(result[0]?.operation).toBe('DELETION')
    expect(result[1]?.operation).toBe('INSERTION')
  })
})
