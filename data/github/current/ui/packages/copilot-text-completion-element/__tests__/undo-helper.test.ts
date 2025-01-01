import {diffContent} from '../undo-helper'

describe('diffContent', () => {
  test('original prefix and current prefix match', () => {
    const originalPrefix = 'original prefix'
    const currentPrefix = 'original prefix'
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('')
    expect(removed).toBe(0)
  })

  test('original prefix has more content', () => {
    const originalPrefix = 'original prefix'
    const currentPrefix = 'original p'
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('refix')
    expect(removed).toBe(0)
  })

  test('original prefix has a content length and character difference', () => {
    const originalPrefix = 'original Prefix'
    const currentPrefix = 'original p'
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('Prefix')
    expect(removed).toBe(1)
  })

  test('captures multiple differences in characters', () => {
    const originalPrefix = 'original PreFIX'
    const currentPrefix = 'original prefix somehow has a lot'
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('PreFIX')
    expect(removed).toBe(24)
  })

  test('current prefix has more content than there was originally', () => {
    const originalPrefix = 'original p'
    const currentPrefix = 'original prefix'
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('')
    expect(removed).toBe(5)
  })

  test('current and original are completely different', () => {
    const originalPrefix = 'i walked'
    const currentPrefix = 'down the road'
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('i walked')
    expect(removed).toBe(13)
  })

  test('current is blank', () => {
    const originalPrefix = 'i walked'
    const currentPrefix = ''
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('i walked')
    expect(removed).toBe(0)
  })

  test('original is blank', () => {
    const originalPrefix = ''
    const currentPrefix = 'i walked'
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('')
    expect(removed).toBe(8)
  })
})
