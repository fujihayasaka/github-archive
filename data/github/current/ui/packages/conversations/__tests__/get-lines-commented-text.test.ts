import type {ThreadSummary} from '../types'
import {getLinesCommentedText} from '../util/get-lines-commented-text'

describe('getLinesCommentedText', () => {
  it('returns empty string when thread has no diffSide', () => {
    const thread = {
      line: 10,
    } as ThreadSummary

    expect(getLinesCommentedText(thread)).toBe('')
  })

  it('returns empty string when thread has no line', () => {
    const thread = {
      diffSide: 'RIGHT',
    } as ThreadSummary

    expect(getLinesCommentedText(thread)).toBe('')
  })

  it('formats single line comment on RIGHT side', () => {
    const thread = {
      diffSide: 'RIGHT',
      line: 10,
    } as ThreadSummary

    expect(getLinesCommentedText(thread)).toBe('Line R10')
  })

  it('formats single line comment on LEFT side', () => {
    const thread = {
      diffSide: 'LEFT',
      line: 15,
    } as ThreadSummary

    expect(getLinesCommentedText(thread)).toBe('Line L15')
  })

  it('formats multi-line comment on same side (RIGHT to RIGHT)', () => {
    const thread = {
      startDiffSide: 'RIGHT',
      startLine: 10,
      diffSide: 'RIGHT',
      line: 15,
    } as ThreadSummary

    expect(getLinesCommentedText(thread)).toBe('Lines R10 to R15')
  })

  it('formats multi-line comment on same side (LEFT to LEFT)', () => {
    const thread = {
      startDiffSide: 'LEFT',
      startLine: 5,
      diffSide: 'LEFT',
      line: 8,
    } as ThreadSummary

    expect(getLinesCommentedText(thread)).toBe('Lines L5 to L8')
  })
})
