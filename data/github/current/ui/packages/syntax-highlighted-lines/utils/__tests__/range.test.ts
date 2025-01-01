import {createRange} from '../range'

describe('createRange', () => {
  test('returns null when element has no firstChild', () => {
    const element = document.createElement('div')
    const result = createRange(element, 0, 1)
    expect(result).toBeNull()
  })

  test('returns null when firstChild has no textContent', () => {
    const element = document.createElement('div')
    element.appendChild(document.createElement('span'))
    const result = createRange(element, 0, 1)
    expect(result).toBeNull()
  })

  test('returns null when start is greater than textContent length', () => {
    const element = document.createElement('div')
    const text = 'Hello'
    element.textContent = text
    const result = createRange(element, text.length + 1, text.length + 2)
    expect(result).toBeNull()
  })

  test('returns null when end is greater than textContent length', () => {
    const element = document.createElement('div')
    const text = 'Hello'
    element.textContent = text
    const result = createRange(element, 0, text.length + 1)
    expect(result).toBeNull()
  })

  test('returns a valid Range object with correct start and end', () => {
    const element = document.createElement('div')
    const text = 'Hello, World!'
    element.textContent = text
    const start = 7
    const end = 12
    const range = createRange(element, start, end)
    expect(range).not.toBeNull()
    expect(range?.startContainer).toBe(element.firstChild)
    expect(range?.startOffset).toBe(start)
    expect(range?.endContainer).toBe(element.firstChild)
    expect(range?.endOffset).toBe(end)
  })
})
