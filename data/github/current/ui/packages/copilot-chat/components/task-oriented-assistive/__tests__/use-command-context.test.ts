import {renderHook} from '@testing-library/react'
import type React from 'react'

import {
  getReducerStateMock,
  getRepositoryMock,
  getSnippetReferenceMock,
  getSymbolReferenceMock,
} from '../../../test-utils/mock-data'
import type {CopilotChatState} from '../../../utils/copilot-chat-reducer'
import type {CopilotChatReference} from '../../../utils/copilot-chat-types'
import {ChatStateProvider} from '../../../utils/CopilotChatContext'
import {useCommandContext} from '../use-command-context'

describe('useCommandContext', () => {
  it('returns pull request context when available', () => {
    const state = {
      context: [
        getSnippetReferenceMock(),
        {
          type: 'pull-request',
          number: 123,
          persona: 'reviewer',
        } as unknown as CopilotChatReference,
      ],
    }

    const {result} = renderHook(() => useCommandContext(), {
      wrapper: getChatStateProvider(state),
    })

    expect(result.current).toEqual({
      type: 'pull-request',
      number: 123,
      persona: 'reviewer',
    })
  })

  describe('fallback to repository topic as context', () => {
    test('when there is no usable context', () => {
      const state = {
        context: [getSnippetReferenceMock(), getSymbolReferenceMock()],
        currentRepository: getRepositoryMock(),
      }

      const {result} = renderHook(() => useCommandContext(), {
        wrapper: getChatStateProvider(state),
      })

      expect(result.current).toStrictEqual({
        type: 'repository',
        ...state.currentRepository,
      })
    })

    test('when context is empty', () => {
      const state = {
        context: [],
        currentRepository: getRepositoryMock(),
      }

      const {result} = renderHook(() => useCommandContext(), {
        wrapper: getChatStateProvider(state),
      })

      expect(result.current).toStrictEqual({
        type: 'repository',
        ...state.currentRepository,
      })
    })

    test('when there is no context', () => {
      const state = {
        context: undefined,
        currentRepository: getRepositoryMock(),
      }

      const {result} = renderHook(() => useCommandContext(), {
        wrapper: getChatStateProvider(state),
      })

      expect(result.current).toStrictEqual({
        type: 'repository',
        ...state.currentRepository,
      })
    })
  })

  it('returns global context when there is no topic', () => {
    const state = {
      context: undefined,
      currentRepository: undefined,
    }

    const {result} = renderHook(() => useCommandContext(), {
      wrapper: getChatStateProvider(state),
    })

    expect(result.current).toStrictEqual({type: 'global'})
  })
})

function getChatStateProvider({...state}: Partial<CopilotChatState>) {
  return function testChatStateProvider({children}: {children: React.ReactNode}) {
    return ChatStateProvider({
      state: {...getReducerStateMock(), ...state},
      children,
    })
  }
}
