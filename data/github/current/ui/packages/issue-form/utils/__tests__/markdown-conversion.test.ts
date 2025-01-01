import {prefixMarkdownCheckbox, prefixMarkdownTextArea, prefixMarkdownTitle} from '../markdown-conversion'

describe('prefixMarkdownTitle', () => {
  const DEFAULT_RESPONSE = '_No response_'

  test('should return content with default header and title when title is provided', () => {
    const result = prefixMarkdownTitle('Title', 'Some content')
    expect(result).toBe('### Title\n\nSome content')
  })

  test('should return content as is when title is not provided', () => {
    const result = prefixMarkdownTitle(null, 'Some content')
    expect(result).toBe('Some content')
  })

  test('should return default response when content is empty and title is not provided', () => {
    const result = prefixMarkdownTitle(null, '')
    expect(result).toBe(DEFAULT_RESPONSE)
  })

  test('should return content with default header and title when content is empty and title is provided', () => {
    const result = prefixMarkdownTitle('Title', '')
    expect(result).toBe(`### Title\n\n${DEFAULT_RESPONSE}`)
  })
})

describe('prefixMarkdownCheckbox', () => {
  test('should return content with checkbox marked when selected is true', () => {
    const result = prefixMarkdownCheckbox('Some task', true)
    expect(result).toBe('- [x] Some task')
  })

  test('should return content with checkbox unmarked when selected is false', () => {
    const result = prefixMarkdownCheckbox('Some task', false)
    expect(result).toBe('- [ ] Some task')
  })
})

describe('prefixMarkdownTextArea', () => {
  const DEFAULT_RESPONSE = '_No response_'

  test('should return formatted content with render when content is not DEFAULT_RESPONSE', () => {
    const result = prefixMarkdownTextArea('Some code', 'javascript')
    expect(result).toBe('```javascript\nSome code\n```')
  })

  test('should return content as is when render is provided but content is DEFAULT_RESPONSE', () => {
    const result = prefixMarkdownTextArea(DEFAULT_RESPONSE, 'javascript')
    expect(result).toBe(DEFAULT_RESPONSE)
  })

  test('should return content as is when render is not provided', () => {
    const result = prefixMarkdownTextArea('Some code', null)
    expect(result).toBe('Some code')
  })

  test('should avoid double-code-blocking', () => {
    const result = prefixMarkdownTextArea('```\nSome code\n```', 'javascript')
    expect(result).toBe('```javascript\nSome code\n```')
  })
})
