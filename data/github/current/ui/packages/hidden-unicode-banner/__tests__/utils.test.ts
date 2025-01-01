import {
  hiddenUnicodeCharacterHTMLString,
  splitAroundHiddenUnicodeCharacters,
  showHiddenUnicodeCharactersRaw,
  hasHiddenUnicodeCharacters,
  getHiddenUnicodeReplacement,
  hiddenUnicodeReplacementMap,
} from '../utils'
import type {SafeHTMLString} from '@github-ui/safe-html'

describe('utils.ts', () => {
  describe('hiddenUnicodeCharacterHTMLString', () => {
    it('should return a SafeHTMLString with the correct HTML structure', () => {
      const replacement = 'U+202A'
      const result = hiddenUnicodeCharacterHTMLString(replacement)
      expect(result).toBe(`<span class="hidden-unicode-replacement" data-code-text="${replacement}"></span>`)
    })
  })

  describe('splitAroundHiddenUnicodeCharacters', () => {
    it('should split text around hidden Unicode characters', () => {
      const input = 'Hello\u202AWorld' as SafeHTMLString
      const result = splitAroundHiddenUnicodeCharacters(input)
      expect(result).toEqual(['Hello', '\u202A', 'World'])
    })

    it('should return the original text if no hidden Unicode characters are present', () => {
      const input = 'Hello World' as SafeHTMLString
      const result = splitAroundHiddenUnicodeCharacters(input)
      expect(result).toEqual([input])
    })
  })

  describe('showHiddenUnicodeCharactersRaw', () => {
    it('should replace hidden Unicode characters with their replacements', () => {
      const input = 'Hello\u202AWorld'
      const result = showHiddenUnicodeCharactersRaw(input)
      expect(result).toBe('HelloU+202AWorld')
    })

    it('should return the original text if no hidden Unicode characters are present', () => {
      const input = 'Hello World'
      const result = showHiddenUnicodeCharactersRaw(input)
      expect(result).toBe(input)
    })
  })

  describe('hasHiddenUnicodeCharacters', () => {
    it('should return true if hidden Unicode characters are present', () => {
      const input = 'Hello\u202AWorld'
      const result = hasHiddenUnicodeCharacters(input)
      expect(result).toBe(true)
    })

    it('should return false if no hidden Unicode characters are present', () => {
      const input = 'Hello World'
      const result = hasHiddenUnicodeCharacters(input)
      expect(result).toBe(false)
    })
  })

  describe('getHiddenUnicodeReplacement', () => {
    it('should return the correct replacement for a hidden Unicode character', () => {
      const char = '\u202A'
      const result = getHiddenUnicodeReplacement(char)
      expect(result).toBe('U+202A')
    })

    it('should return undefined for a character that is not a hidden Unicode character', () => {
      const char = 'A'
      const result = getHiddenUnicodeReplacement(char)
      expect(result).toBeUndefined()
    })
  })

  describe('hiddenUnicodeReplacementMap', () => {
    it('should contain all expected hidden Unicode characters and their replacements', () => {
      const entries = Array.from(hiddenUnicodeReplacementMap.entries())
      expect(entries).toContainEqual(['\u202A', 'U+202A'])
      expect(entries).toContainEqual(['\u202B', 'U+202B'])
      expect(entries).toContainEqual(['\u202C', 'U+202C'])
      expect(entries).toContainEqual(['\u202D', 'U+202D'])
      expect(entries).toContainEqual(['\u202E', 'U+202E'])
      expect(entries).toContainEqual(['\u2066', 'U+2066'])
      expect(entries).toContainEqual(['\u2067', 'U+2067'])
      expect(entries).toContainEqual(['\u2068', 'U+2068'])
      expect(entries).toContainEqual(['\u2069', 'U+2069'])
      expect(entries).toContainEqual(['\u{E0001}', 'U+E0001'])
      expect(entries).toContainEqual(['\u{E007F}', 'U+E007F'])
    })
  })
})
