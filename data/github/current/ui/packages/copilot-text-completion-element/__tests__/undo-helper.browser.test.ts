import {describe, expect, it} from '@github-ui/tests'
import {diffContent} from '../undo-helper'

describe('diffContent', () => {
  it('original prefix and current prefix match', () => {
    const originalPrefix = 'original prefix'
    const currentPrefix = 'original prefix'
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('')
    expect(removed).toBe(0)
  })

  it('original prefix has more content', () => {
    const originalPrefix = 'original prefix'
    const currentPrefix = 'original p'
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('refix')
    expect(removed).toBe(0)
  })

  it('original prefix has a content length and character difference', () => {
    const originalPrefix = 'original Prefix'
    const currentPrefix = 'original p'
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('Prefix')
    expect(removed).toBe(1)
  })

  it('captures multiple differences in characters', () => {
    const originalPrefix = 'original PreFIX'
    const currentPrefix = 'original prefix somehow has a lot'
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('PreFIX')
    expect(removed).toBe(24)
  })

  it('current prefix has more content than there was originally', () => {
    const originalPrefix = 'original p'
    const currentPrefix = 'original prefix'
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('')
    expect(removed).toBe(5)
  })

  it('current and original are completely different', () => {
    const originalPrefix = 'i walked'
    const currentPrefix = 'down the road'
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('i walked')
    expect(removed).toBe(13)
  })

  it('current is blank', () => {
    const originalPrefix = 'i walked'
    const currentPrefix = ''
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('i walked')
    expect(removed).toBe(0)
  })

  it('original is blank', () => {
    const originalPrefix = ''
    const currentPrefix = 'i walked'
    const {added, removed} = diffContent(originalPrefix, currentPrefix)
    expect(added).toBe('')
    expect(removed).toBe(8)
  })
})
