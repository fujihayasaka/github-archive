import {pluralize} from '../pluralize'

describe('pluralize', () => {
  it('should return the plural form of a word when count is not 1', () => {
    expect(pluralize('word', 0)).toBe('words')
    expect(pluralize('word', 2)).toBe('words')
    expect(pluralize('word', 3)).toBe('words')
  })

  it('should return the singular form of a word when count is 1', () => {
    expect(pluralize('word', 1)).toBe('word')
  })

  it('should return the plural form of a word when count is not 1 and a plural form is provided', () => {
    expect(pluralize('word', 0, 'wordy')).toBe('wordy')
    expect(pluralize('word', 2, 'wordy')).toBe('wordy')
    expect(pluralize('word', 3, 'wordy')).toBe('wordy')
  })
})
