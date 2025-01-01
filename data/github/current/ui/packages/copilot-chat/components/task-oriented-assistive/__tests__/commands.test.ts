import {renderHook} from '@testing-library/react'

import {getCommandSuggestions} from '../commands'

describe('getCommandSuggestions', () => {
  it('should return an empty array without a context type', () => {
    const {result} = renderHook(() => getCommandSuggestions())

    expect(result.current).toEqual([])
  })

  it('should return an empty array for an unknown context type', () => {
    const {result} = renderHook(() => getCommandSuggestions('unknown'))

    expect(result.current).toEqual([])
  })

  describe('pull-request context', () => {
    it('should not include commands for all parent contexts', () => {
      const {result} = renderHook(() => getCommandSuggestions('pull-request'))

      expect(result.current.map(command => command.question)).toStrictEqual([
        'Proof read this pull request',
        'Highlight focus areas for review in this pull request',
        'Explain this pull request',
        'Catch me up on the reviews',
        'Catch me up on the changes',
        'Analyze build failures',
      ])
    })

    describe('persona', () => {
      it('should return commands for the "author" persona', () => {
        const {result} = renderHook(() => getCommandSuggestions('pull-request', 'author'))

        expect(result.current.map(command => command.question)).toStrictEqual([
          'Proof read this pull request',
          'Catch me up on the reviews',
          'Analyze build failures',
        ])
      })

      it('should return commands for the "reviewer" persona', () => {
        const {result} = renderHook(() => getCommandSuggestions('pull-request', 'reviewer'))

        expect(result.current.map(command => command.question)).toStrictEqual([
          'Highlight focus areas for review in this pull request',
          'Catch me up on the changes',
        ])
      })

      it('should return commands for the "other" persona', () => {
        const {result} = renderHook(() => getCommandSuggestions('pull-request', 'other'))

        expect(result.current.map(command => command.question)).toStrictEqual(['Explain this pull request'])
      })
    })
  })

  describe('repository context', () => {
    it('should not include commands for all parent contexts', () => {
      const {result} = renderHook(() => getCommandSuggestions('repository'))

      expect(result.current.map(command => command.question)).toStrictEqual([
        'Tell me about this repository',
        'How to get started with this repository',
        'Summarize activity for this repository in the last day',
      ])
    })
  })

  describe('global context', () => {
    it('should not include commands for all parent contexts', () => {
      const {result} = renderHook(() => getCommandSuggestions('global'))

      expect(result.current.map(command => command.question)).toStrictEqual([
        'Help me get started with Copilot',
        'Summarize my activity in the last week',
      ])
    })
  })
})
