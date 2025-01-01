import {renderHook} from '@testing-library/react'

import {useCommands} from '../use-commands'

describe('useCommands', () => {
  it('should return an empty array without a context type', () => {
    const {result} = renderHook(() => useCommands())

    expect(result.current).toEqual([])
  })

  it('should return an empty array for an unknown context type', () => {
    const {result} = renderHook(() => useCommands('unknown'))

    expect(result.current).toEqual([])
  })

  describe('pull-request context', () => {
    it('should include commands for all parent contexts', () => {
      const {result} = renderHook(() => useCommands('pull-request'))

      expect(result.current.map(command => command.name)).toStrictEqual([
        'Proof read this pull request',
        'Highlight focus areas for review in this pull request',
        'Explain this pull request',
        'Catch me up on the reviews',
        'Catch me up on the changes',
        'Analyze build failures',
        'Tell me about this repository',
        'How to get started with this repository',
        'Summarize activity for this repository in the last day',
        'Help me get started with Copilot',
        'Summarize my activity in the last week',
      ])
    })

    describe('persona', () => {
      it('should return commands for the "author" persona', () => {
        const {result} = renderHook(() => useCommands('pull-request', 'author'))

        expect(result.current.map(command => command.name)).toStrictEqual([
          'Proof read this pull request',
          'Catch me up on the reviews',
          'Analyze build failures',
          'Tell me about this repository',
          'How to get started with this repository',
          'Summarize activity for this repository in the last day',
          'Help me get started with Copilot',
          'Summarize my activity in the last week',
        ])
      })

      it('should return commands for the "reviewer" persona', () => {
        const {result} = renderHook(() => useCommands('pull-request', 'reviewer'))

        expect(result.current.map(command => command.name)).toStrictEqual([
          'Highlight focus areas for review in this pull request',
          'Catch me up on the changes',
          'Tell me about this repository',
          'How to get started with this repository',
          'Summarize activity for this repository in the last day',
          'Help me get started with Copilot',
          'Summarize my activity in the last week',
        ])
      })

      it('should return commands for the "other" persona', () => {
        const {result} = renderHook(() => useCommands('pull-request', 'other'))

        expect(result.current.map(command => command.name)).toStrictEqual([
          'Explain this pull request',
          'Tell me about this repository',
          'How to get started with this repository',
          'Summarize activity for this repository in the last day',
          'Help me get started with Copilot',
          'Summarize my activity in the last week',
        ])
      })
    })
  })

  describe('repository context', () => {
    it('should include commands for all parent contexts', () => {
      const {result} = renderHook(() => useCommands('repository'))

      expect(result.current.map(command => command.name)).toStrictEqual([
        'Tell me about this repository',
        'How to get started with this repository',
        'Summarize activity for this repository in the last day',
        'Help me get started with Copilot',
        'Summarize my activity in the last week',
      ])
    })
  })

  describe('global context', () => {
    it('should include commands for all parent contexts', () => {
      const {result} = renderHook(() => useCommands('global'))

      expect(result.current.map(command => command.name)).toStrictEqual([
        'Help me get started with Copilot',
        'Summarize my activity in the last week',
      ])
    })
  })

  describe('filtering', () => {
    it('should return only commands that match the filter', () => {
      const {result} = renderHook(() => useCommands('pull-request', undefined, 'explain'))

      expect(result.current.map(command => command.name)).toStrictEqual(['Explain this pull request'])
    })

    describe('when no commands match the filter', () => {
      it('should return a custom command', () => {
        const {result} = renderHook(() => useCommands('pull-request', undefined, 'foo bar'))

        expect(result.current).toEqual([
          expect.objectContaining({
            type: 'custom',
            context: 'global',
            name: 'foo bar',
            prompt: 'foo bar',
          }),
        ])
      })
    })
  })
})
