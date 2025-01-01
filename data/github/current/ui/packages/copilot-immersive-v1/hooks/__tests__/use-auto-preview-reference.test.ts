import {referenceID} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CopilotChatMessage, FileReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {renderHook} from '@testing-library/react'
import {useLocation, useSearchParams} from 'react-router-dom'

import {useAutoPreviewReference} from '../use-auto-preview-reference'
import {useOnReferenceSelect} from '../use-on-reference-select'

jest.mock('@github-ui/copilot-chat/utils/CopilotChatContext')
jest.mock('react-router-dom')
jest.mock('../use-on-reference-select')

const mockReference: FileReference = {
  type: 'file',
  url: 'url',
  path: 'file1',
  repoID: 1,
  repoOwner: 'owner',
  repoName: 'repo',
  ref: 'main',
  commitOID: 'sha',
}

const mockReferenceId = referenceID(mockReference)

describe('useAutoPreviewReference', () => {
  const mockOnReferenceSelect = jest.fn()
  const mockSetSearchParams = jest.fn()
  const mockMessages: CopilotChatMessage[] = [
    {
      id: 'msg1',
      role: 'user',
      createdAt: '2024-01-01T00:00:00Z',
      threadID: 'thread1',
      references: [mockReference],
      content: '',
    },
  ]

  beforeEach(() => {
    jest.clearAllMocks()
    ;(useOnReferenceSelect as jest.Mock).mockReturnValue(mockOnReferenceSelect)
    ;(useSearchParams as jest.Mock).mockReturnValue([null, mockSetSearchParams])
  })

  it('calls onReferenceSelect when only reference_id is present', () => {
    ;(useChatState as jest.Mock).mockReturnValue({
      messages: mockMessages,
      currentReferences: [mockReference],
    })
    ;(useLocation as jest.Mock).mockReturnValue({search: `?reference_id=${mockReferenceId}`})
    renderHook(() => useAutoPreviewReference())
    expect(mockOnReferenceSelect).toHaveBeenCalledWith(mockReference)
  })

  it('calls onReferenceSelect with correct message when both reference_id and message_index are present', () => {
    ;(useChatState as jest.Mock).mockReturnValue({
      messages: mockMessages,
      currentReferences: [mockReference],
    })
    ;(useLocation as jest.Mock).mockReturnValue({search: `?reference_id=${mockReferenceId}&message_index=0`})
    renderHook(() => useAutoPreviewReference())
    expect(mockOnReferenceSelect).toHaveBeenCalledWith(mockReference)
  })

  it('clears search params after reference selection', () => {
    ;(useChatState as jest.Mock).mockReturnValue({
      messages: mockMessages,
      currentReferences: [mockReference],
    })
    ;(useLocation as jest.Mock).mockReturnValue({search: `?reference_id=${mockReferenceId}&message_index=0`})

    renderHook(() => useAutoPreviewReference())

    expect(mockSetSearchParams).toHaveBeenCalledWith(expect.any(Function))

    // Test the function passed to setSearchParams
    const setSearchParamsCallback = mockSetSearchParams.mock.calls[0][0] as (params: URLSearchParams) => URLSearchParams
    const mockSearchParams = new URLSearchParams('reference_id=test&message_index=0&other_param=value')
    const result: URLSearchParams = setSearchParamsCallback(mockSearchParams)

    expect(result.has('reference_id')).toBe(false)
    expect(result.has('message_index')).toBe(false)
    expect(result.has('other_param')).toBe(true) // Other params should remain
  })
})
