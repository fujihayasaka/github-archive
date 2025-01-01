import type {CopilotChatThread, CustomCopilotId} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {customCopilotApiPath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {getCustomCopilotMock} from '@github-ui/custom-copilots/test-utils/mock-data'
import type {CustomCopilotResource} from '@github-ui/custom-copilots/types'
import {mockFetch} from '@github-ui/mock-fetch'
import {renderHook} from '@github-ui/react-core/test-utils'
import {act, waitFor} from '@testing-library/react'

import {useUpsertCopilotSpace} from '../use-upsert-copilot-space'

const mockDispatch = jest.fn()

jest.mock('@github-ui/copilot-chat/CopilotChatManagerContext', () => {
  return {
    ...jest.requireActual('@github-ui/copilot-chat/CopilotChatManagerContext'),
    useChatManager: () => {
      return {
        fetchCustomCopilot: jest.fn(),
        dispatch: mockDispatch,
        maxMessagesReached: jest.fn(() => false),
        getSelectedThread: jest.fn(),
        clearCurrentReferences: jest.fn(),
        cancelThreadReload: jest.fn(),
        sortThreads: jest.fn((threads: Map<string, CopilotChatThread>): CopilotChatThread[] =>
          Array.from(threads.values()),
        ),
      }
    },
  }
})

const mockCopilot = getCustomCopilotMock()

describe('useUpsertCopilotSpace', () => {
  beforeEach(() => {
    mockDispatch.mockClear()
    // mockFetch is cleared automatically by its afterEach hook
  })

  it('should create a new copilot space', async () => {
    const input = {
      name: 'New Copilot',
      iconType: 'beaker',
      iconColor: 'blue',
      description: 'A brand new copilot',
      generalInstructions: 'Be creative',
      ownerId: 1,
      ownerType: 'User',
      resources: [
        {
          type: 'github_file',
          repositoryId: 456,
          filePath: 'src/main.ts',
        } as CustomCopilotResource,
      ],
    }
    const expectedPayload = {
      // eslint-disable-next-line camelcase
      custom_copilot: {
        // eslint-disable-next-line camelcase
        owner_id: 1,
        // eslint-disable-next-line camelcase
        owner_type: 'User',
        name: 'New Copilot',
        // eslint-disable-next-line camelcase
        icon_type: 'beaker',
        // eslint-disable-next-line camelcase
        icon_color: 'blue',
        description: 'A brand new copilot',
        // eslint-disable-next-line camelcase
        general_instructions: 'Be creative',
        // eslint-disable-next-line camelcase
        resources_attributes: [
          {
            id: undefined,
            // eslint-disable-next-line camelcase
            resource_type: 'github_file',
            // eslint-disable-next-line camelcase
            metadata: {repository_id: 456, file_path: 'src/main.ts'},
          },
        ],
      },
    }
    const mockResponse = {...mockCopilot, ...input, id: 'new_copilot_456'}

    mockFetch.mockRouteOnce('/custom_copilots', mockResponse)

    const {result} = renderHook(() => useUpsertCopilotSpace())

    await act(async () => {
      await result.current.upsertCopilotSpace(input)
    })

    expect(mockFetch.fetch).toHaveBeenCalledWith(
      '/custom_copilots',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify(expectedPayload),
      }),
    )
    await waitFor(() => {
      expect(result.current.isSuccess).toBe(true)
    })
    expect(result.current.data).toEqual(mockResponse)
    expect(mockDispatch).toHaveBeenCalledWith({
      type: 'SET_CUSTOM_COPILOT',
      customCopilot: mockResponse,
    })
  })

  it('should update an existing copilot space', async () => {
    const copilotId: CustomCopilotId = {id: 789} // Fix type error: id should be number
    const input = {
      name: 'Updated Copilot Name',
      description: 'Updated description',
      resources: [
        {
          databaseId: 1,
          type: 'github_file',
          repositoryId: 456,
          filePath: 'src/main.ts',
        } as CustomCopilotResource,
        {
          type: 'free_text',
          name: 'Instructions',
          text: 'Some free text instructions',
        } as CustomCopilotResource,
        {
          databaseId: 3,
          type: 'github_file',
          repositoryId: 789,
          filePath: 'docs/README.md',
          markedForDestroy: true, // Mark this resource for deletion
        } as CustomCopilotResource,
      ],
    }
    const expectedPayload = {
      // eslint-disable-next-line camelcase
      custom_copilot: {
        // eslint-disable-next-line camelcase
        owner_id: undefined,
        // eslint-disable-next-line camelcase
        owner_type: undefined,
        name: 'Updated Copilot Name',
        // eslint-disable-next-line camelcase
        icon_type: undefined,
        // eslint-disable-next-line camelcase
        icon_color: undefined,
        description: 'Updated description',
        // eslint-disable-next-line camelcase
        general_instructions: undefined,
        // eslint-disable-next-line camelcase
        resources_attributes: [
          {
            id: 1,
            // eslint-disable-next-line camelcase
            resource_type: 'github_file',
            // eslint-disable-next-line camelcase
            metadata: {repository_id: 456, file_path: 'src/main.ts'},
          },
          {
            id: undefined,
            // eslint-disable-next-line camelcase
            resource_type: 'free_text',
            metadata: {text: 'Some free text instructions', name: 'Instructions'},
          },
          {
            id: 3,
            // eslint-disable-next-line camelcase
            resource_type: 'github_file',
            _destroy: true,
            // eslint-disable-next-line camelcase
            metadata: {repository_id: 789, file_path: 'docs/README.md'},
          },
        ],
      },
    }
    const mockResponse = {...mockCopilot, ...input, id: copilotId}
    const url = customCopilotApiPath(copilotId)

    const fetchMock = mockFetch.mockRouteOnce(url, mockResponse)

    const {result} = renderHook(() => useUpsertCopilotSpace(copilotId))

    await act(async () => {
      await result.current.upsertCopilotSpace(input)
    })

    expect(fetchMock).toHaveBeenCalledWith(
      url,
      expect.objectContaining({
        method: 'PUT',
        body: JSON.stringify(expectedPayload),
      }),
    )
    await waitFor(() => {
      expect(result.current.isSuccess).toBe(true)
    })
    expect(result.current.data).toEqual(mockResponse)
    expect(mockDispatch).toHaveBeenCalledWith({
      type: 'SET_CUSTOM_COPILOT',
      customCopilot: mockResponse,
    })
  })

  it('should handle API errors during creation', async () => {
    const input = {name: 'Error Copilot'}
    const errorResponse = {errorMessages: ['Name cannot be blank']}

    const fetchMock = mockFetch.mockRouteOnce('/custom_copilots', errorResponse, {ok: false, status: 422})

    const {result} = renderHook(() => useUpsertCopilotSpace())

    await act(async () => {
      await expect(result.current.upsertCopilotSpace(input)).rejects.toEqual(errorResponse.errorMessages)
    })

    expect(fetchMock).toHaveBeenCalledWith(
      '/custom_copilots',
      expect.objectContaining({
        method: 'POST',
        // eslint-disable-next-line camelcase
        body: JSON.stringify({custom_copilot: {name: 'Error Copilot'}}), // Simplified body for error case
      }),
    )
    await waitFor(() => {
      expect(result.current.isError).toBe(true)
    })
    expect(result.current.error).toEqual(errorResponse.errorMessages)
    expect(mockDispatch).not.toHaveBeenCalled()
  })

  it('should handle API errors during update', async () => {
    const copilotId: CustomCopilotId = {id: 42}
    const input = {name: 'Updated Error Copilot'}
    const errorResponse = {errorMessages: ['Update failed']}
    const url = customCopilotApiPath(copilotId)

    const fetchMock = mockFetch.mockRouteOnce(url, errorResponse, {ok: false, status: 500})

    const {result} = renderHook(() => useUpsertCopilotSpace(copilotId))

    await act(async () => {
      await expect(result.current.upsertCopilotSpace(input)).rejects.toEqual(errorResponse.errorMessages)
    })

    expect(fetchMock).toHaveBeenCalledWith(
      url,
      expect.objectContaining({
        method: 'PUT',
        // eslint-disable-next-line camelcase
        body: JSON.stringify({custom_copilot: {name: 'Updated Error Copilot'}}), // Simplified body for error case
      }),
    )
    await waitFor(() => {
      expect(result.current.isError).toBe(true)
    })
    expect(result.current.error).toEqual(errorResponse.errorMessages)
    expect(mockDispatch).not.toHaveBeenCalled()
  })

  it('handles uploaded_text_file resources', async () => {
    const input = {
      resources: [
        {
          id: 'upload-123',
          type: 'uploaded_text_file',
          name: 'document.txt',
          copilotChatAttachmentId: 1,
          markedForDestroy: false,
        } satisfies CustomCopilotResource,
      ],
    }

    const expectedPayload = {
      // eslint-disable-next-line camelcase
      custom_copilot: {
        // eslint-disable-next-line camelcase
        resources_attributes: input.resources.map(resource => ({
          // eslint-disable-next-line camelcase
          resource_type: resource.type,
          _destroy: resource.markedForDestroy,
          metadata: {
            name: resource.name,
            // eslint-disable-next-line camelcase
            copilot_chat_attachment_id: resource.copilotChatAttachmentId,
          },
        })),
      },
    }

    const mockResponse = {...mockCopilot, ...input, id: 'new_copilot_789'}
    mockFetch.mockRouteOnce('/custom_copilots', mockResponse)

    const {result} = renderHook(() => useUpsertCopilotSpace())

    await act(() => result.current.upsertCopilotSpace(input))
    await waitFor(() => expect(result.current.isSuccess).toBe(true))

    expect(mockFetch.fetch).toHaveBeenCalledWith(
      '/custom_copilots',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify(expectedPayload),
      }),
    )

    expect(mockDispatch).toHaveBeenCalled()
  })
})
