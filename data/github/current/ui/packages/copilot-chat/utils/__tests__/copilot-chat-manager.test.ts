import {mockClientEnv} from '@github-ui/client-env/mock'

import {
  getDefaultReducerState,
  getImageReferenceMock,
  getMessageMock,
  getModelMock,
  getReferencesMock,
  getRepositoryMock,
  getRepositoryReferenceMock,
  getSnippetReferenceMock,
  getThreadMock,
} from '../../test-utils/mock-data'
import {MockReader} from '../../test-utils/mock-reader'
import {CopilotChatManager} from '../copilot-chat-manager'
import type {Reader} from '../copilot-chat-message-streamer'
import {type CopilotChatAction, copilotChatReducer, type CopilotChatState} from '../copilot-chat-reducer'
import {CopilotChatService} from '../copilot-chat-service'
import {
  type ChatError,
  CopilotChatIntents,
  type CopilotChatMessage,
  type CopilotChatModel,
  type CopilotChatThread,
  type CopilotCustomInstructions,
  type CustomCopilotId,
  type FileReference,
  type MessageStreamingResponseComplete,
  type MessageStreamingResponseThreadTitle,
  type RepoInstructionsReference,
  type RepositoryReference,
} from '../copilot-chat-types'
import {copilotFeatureFlags} from '../copilot-feature-flags'
import {CopilotImageAttacher} from '../copilot-image-attacher'
import {UploadableFileAttachment} from '../uploadable-file-attachment'

jest.mock('../copilot-chat-service')
jest.mock('../copilot-chat-message-streamer', () => {
  return {
    CopilotChatMessageStreamer: jest.fn().mockImplementation((reader: Reader) => {
      return {
        stream: jest.fn(),
        reader,
      }
    }),
  }
})

describe('CopilotChatManager', () => {
  let manager: CopilotChatManager
  let chatService: CopilotChatService
  let dispatch: jest.Mock
  let state: CopilotChatState

  beforeEach(() => {
    dispatch = jest.fn()

    chatService = new CopilotChatService('', [])
    state = getDefaultReducerState('2', undefined, 'immersive')

    manager = new CopilotChatManager(dispatch, 'apiURL', [], () => state, undefined, chatService, false, [])
  })

  describe('sendChatMessage', () => {
    it('should send a new chat message', async () => {
      const thread = getThreadMock()
      const content = 'Hello, world!'
      const references = getReferencesMock()
      const topic = getRepositoryMock()

      chatService.createMessageStreaming = jest.fn().mockResolvedValue({
        response: {
          body: {
            getReader: () => new MockReader([]),
          },
        },
      })

      await manager.sendChatMessage({thread, content, references, topic})

      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'MESSAGE_ADDED'}))
      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'WAITING_ON_COPILOT', loading: true}))
    })

    describe('processStreamingMessage', () => {
      const customCopilotRef: FileReference = {
        type: 'file',
        url: '',
        path: './path/to/file.txt',
        repoID: 123,
        repoOwner: 'monalisa',
        repoName: 'smile',
        ref: 'main',
        commitOID: 'abc123',
        refOrigin: 'custom_copilot',
      }

      it('filters custom copilot references of the complete message', async () => {
        const thread = getThreadMock()
        const messageResponse: MessageStreamingResponseComplete = {
          type: 'complete', // Explicitly set the type as "complete"
          model: 'gpt-4',
          role: 'assistant',
          id: 'mock-id',
          turnId: 'mock-turn-id',
          createdAt: new Date().toISOString(),
          intent: 'conversation',
          references: [customCopilotRef],
        }

        await manager['processStreamingMessage'](thread, messageResponse)

        expect(dispatch).toHaveBeenNthCalledWith(
          1,
          expect.objectContaining({
            type: 'MESSAGE_STREAMING_COMPLETED',
            messageResponse: expect.objectContaining({
              references: [],
            }),
          }),
        )
        // Verify there are no references
        expect(dispatch.mock.calls[0][0].messageResponse.references).toHaveLength(0)
      })

      it('updates the title of a thread', async () => {
        const thread = getThreadMock()
        const messageResponse: MessageStreamingResponseThreadTitle = {
          type: 'threadTitle',
          title: 'A new thread title',
        }

        await manager['processStreamingMessage'](thread, messageResponse)

        expect(dispatch).toHaveBeenNthCalledWith(
          1,
          expect.objectContaining({
            type: 'THREAD_UPDATED',
            thread: expect.objectContaining({
              name: 'A new thread title',
            }),
          }),
        )
      })
    })

    describe('custom instructions', () => {
      let orgCustomInstructions: CopilotCustomInstructions
      let repoCustomInstructions: CopilotCustomInstructions
      let repositoryReference: RepositoryReference
      let createMessageStreamingMock: jest.Mock

      beforeEach(() => {
        orgCustomInstructions = {
          type: 'Organization',
          prompt: 'beep',
          owner: 'github',
        }
        repoCustomInstructions = {
          type: 'Repository',
          prompt: 'boop',
          owner: 'github/github',
        }
        repositoryReference = getRepositoryReferenceMock()
        repositoryReference.customInstructions = [repoCustomInstructions, orgCustomInstructions]

        createMessageStreamingMock = jest.fn().mockResolvedValue({
          response: {
            body: {
              getReader: () => new MockReader([]),
            },
          },
        })
        chatService.createMessageStreaming = createMessageStreamingMock
      })

      it('no custom instructions', async () => {
        await manager.sendChatMessage({
          thread: getThreadMock(),
          content: 'Hello, world!',
          references: getReferencesMock(),
        })

        expect(dispatch).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'MESSAGE_ADDED',
            repoHasCustomInstructions: false,
            usedRepoCustomInstructions: false,
          }),
        )
        expect(createMessageStreamingMock.mock.lastCall[0].customInstructions).toEqual([])
      })

      it('has custom instructions from topic but feature is disabled', async () => {
        const topic = getRepositoryMock()
        topic.customInstructions = repositoryReference.customInstructions
        await manager.sendChatMessage({
          thread: getThreadMock(),
          content: 'Hello, world!',
          references: getReferencesMock(),
          topic,
        })

        expect(dispatch).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'MESSAGE_ADDED',
            repoHasCustomInstructions: true,
            usedRepoCustomInstructions: false,
          }),
        )
        expect(createMessageStreamingMock.mock.lastCall[0].customInstructions).toEqual([])
      })

      it('has custom instructions from topic and feature is enabled', async () => {
        mockClientEnv({
          featureFlags: ['copilot_chat_repo_custom_instructions'],
        })

        const topic = getRepositoryMock()
        topic.customInstructions = repositoryReference.customInstructions
        await manager.sendChatMessage({
          thread: getThreadMock(),
          content: 'Hello, world!',
          references: getReferencesMock(),
          topic,
        })

        expect(dispatch).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'MESSAGE_ADDED',
            repoHasCustomInstructions: true,
            usedRepoCustomInstructions: true,
          }),
        )
        expect(createMessageStreamingMock.mock.lastCall[0].customInstructions).toEqual(
          repositoryReference.customInstructions?.map(i => i.prompt),
        )
      })

      it('has custom instructions from references if topics as references is enabled', async () => {
        mockClientEnv({
          featureFlags: ['copilot_chat_repo_custom_instructions', 'copilot_topics_as_references'],
        })

        await manager.sendChatMessage({
          thread: getThreadMock(),
          content: 'Hello, world!',
          references: [],
          customInstructions: {
            type: 'Assistant',
            prompt: 'assistant instructions',
            owner: '',
          },
        })

        expect(dispatch).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'MESSAGE_ADDED',
            repoHasCustomInstructions: false,
            usedRepoCustomInstructions: false,
          }),
        )
        expect(createMessageStreamingMock.mock.lastCall[0].customInstructions).toEqual(['assistant instructions'])
      })

      it('has assistant custom instructions if available', async () => {
        mockClientEnv({
          featureFlags: ['copilot_chat_repo_custom_instructions', 'copilot_topics_as_references'],
        })

        await manager.sendChatMessage({
          thread: getThreadMock(),
          content: 'Hello, world!',
          references: [repositoryReference, getSnippetReferenceMock()],
        })

        expect(dispatch).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'MESSAGE_ADDED',
            repoHasCustomInstructions: true,
            usedRepoCustomInstructions: true,
          }),
        )
        expect(createMessageStreamingMock.mock.lastCall[0].customInstructions).toEqual(
          repositoryReference.customInstructions?.map(i => i.prompt),
        )
      })
    })

    describe('intent', () => {
      it('should send a chat message with the conversation intent by default', async () => {
        const createMessageStreamingMock = jest.fn().mockResolvedValue({
          response: {
            body: {
              getReader: () => new MockReader([]),
            },
          },
        })

        chatService.createMessageStreaming = createMessageStreamingMock

        await manager.sendChatMessage({
          thread: getThreadMock(),
          content: 'Hello, world!',
          references: getReferencesMock(),
        })

        expect(createMessageStreamingMock).toHaveBeenCalledTimes(1)
        expect(createMessageStreamingMock.mock.lastCall[0].intent).toEqual(CopilotChatIntents.conversation)
      })

      it('should send a chat message with the provided intent', async () => {
        const createMessageStreamingMock = jest.fn().mockResolvedValue({
          response: {
            body: {
              getReader: () => new MockReader([]),
            },
          },
        })

        chatService.createMessageStreaming = createMessageStreamingMock

        await manager.sendChatMessage({
          intent: CopilotChatIntents.actionsAgent,
          thread: getThreadMock(),
          content: 'Hello, world!',
          references: getReferencesMock(),
        })

        expect(createMessageStreamingMock).toHaveBeenCalledTimes(1)
        expect(createMessageStreamingMock.mock.lastCall[0].intent).toEqual(CopilotChatIntents.actionsAgent)
      })
    })

    it('should send a chat message with media content', async () => {
      mockClientEnv({
        featureFlags: ['copilot_chat_attach_images'],
      })

      const thread = getThreadMock()
      const content = 'Summarize this photo'
      const references = getReferencesMock()
      const originalReferencesCount = references.length
      const topic = getRepositoryMock()
      const imageReference = getImageReferenceMock(['Some test content'])
      references.push(imageReference)

      const createMessageStreamingMock = jest.fn().mockResolvedValue({
        response: {
          body: {
            getReader: () => new MockReader([]),
          },
        },
      })

      chatService.createMessageStreaming = createMessageStreamingMock

      await manager.sendChatMessage({thread, content, references, topic})

      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'MESSAGE_ADDED'}))
      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'WAITING_ON_COPILOT', loading: true}))

      expect(createMessageStreamingMock).toHaveBeenCalledTimes(1)
      const mediaContent = createMessageStreamingMock.mock.lastCall[0].mediaContent
      const refs = createMessageStreamingMock.mock.lastCall[0].references

      expect(mediaContent[0].mediaType).toEqual(imageReference.mediaType)
      expect(mediaContent[0].url).toEqual(imageReference.imageUrl)
      expect(refs.length).toEqual(originalReferencesCount)
    })

    it('should send a chat message using the pending thread id when available', async () => {
      const customCopilotId = {id: 123, owner: 'test-copilot-id'} as CustomCopilotId
      manager.setPendingThreadId('test-thread-id', customCopilotId)
      const threadId = manager.getPendingThreadId(customCopilotId)
      expect(threadId).toEqual('test-thread-id')

      // Mock manager.getThreadById to return a thread with the pending thread ID
      manager.getThreadById = jest.fn().mockReturnValue({id: threadId})

      // Spy on the private method before the test
      // @ts-expect-error: We're spying on a private method for testing
      const sendNewMessageSpy = jest.spyOn(manager, 'sendNewMessage')

      const content = 'Hello, world!'
      const references = getReferencesMock()
      const topic = getRepositoryMock()
      chatService.createMessageStreaming = jest.fn().mockResolvedValue({
        response: {
          body: {
            getReader: () => new MockReader([]),
          },
        },
      })
      await manager.sendChatMessage({thread: null, content, references, topic, customCopilotId})
      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'MESSAGE_ADDED'}))
      expect(sendNewMessageSpy).toHaveBeenCalledWith(
        {id: threadId},
        content,
        [],
        'conversation',
        references,
        topic,
        undefined,
        undefined,
        undefined,
        undefined,
        customCopilotId,
        undefined,
        undefined,
        undefined,
        undefined,
        undefined,
      )
    })
  })

  describe('retryLastUnsuccessfulChatMessage', () => {
    it('should retry the last chat error message', async () => {
      const thread = getThreadMock()

      // Set up state with a user message and an error message
      let action: CopilotChatAction = {type: 'MESSAGES_UPDATED', messages: [getMessageMock()], state: 'loaded'}
      state = copilotChatReducer(state, action)

      const errorMessage = {...getMessageMock(), error: {} as ChatError}
      action = {type: 'MESSAGE_ADDED', message: errorMessage}
      state = copilotChatReducer(state, action)

      chatService.createMessageStreaming = jest.fn().mockResolvedValue({
        response: {
          body: {
            getReader: () => new MockReader([]),
          },
        },
      })

      await manager.retryLastUnsuccessfulChatMessage(thread)

      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'MESSAGES_CLEAR_LAST_ERROR'}))
      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'MESSAGE_ADDED'}))
      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'WAITING_ON_COPILOT', loading: true}))
    })

    it('should retry the last chat interrupted message', async () => {
      const thread = getThreadMock()

      // Set up state with a user message and an interrupted message
      let action: CopilotChatAction = {type: 'MESSAGES_UPDATED', messages: [getMessageMock()], state: 'loaded'}
      state = copilotChatReducer(state, action)

      const interruptedMessage = {...getMessageMock(), interrupted: true}
      action = {type: 'MESSAGE_ADDED', message: interruptedMessage}
      state = copilotChatReducer(state, action)

      chatService.createMessageStreaming = jest.fn().mockResolvedValue({
        response: {
          body: {
            getReader: () => new MockReader([]),
          },
        },
      })

      await manager.retryLastUnsuccessfulChatMessage(thread)

      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'MESSAGES_CLEAR_LAST_ERROR'}))
      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'MESSAGE_ADDED'}))
      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'WAITING_ON_COPILOT', loading: true}))
    })
  })

  describe('setSelectedMessage', () => {
    it('should dispatch an event to set selected message', () => {
      const message = getMessageMock()

      // Set up state with a user message
      const action: CopilotChatAction = {type: 'MESSAGE_ADDED', message}
      state = copilotChatReducer(state, action)

      manager.setSelectedMessage(message)

      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'MESSAGES_SET_SELECTED_MESSAGE'}))
    })
  })

  describe('handleFeedback', () => {
    it('should dispatch an event to update the message feedback', () => {
      const message = getMessageMock()
      manager.handleFeedback(message, 'POSITIVE')

      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'MESSAGE_FEEDBACK'}))
    })
  })

  describe('unselectPreviousChildMessage', () => {
    it('should dispatch an event to reset the pointer to the previous child message', () => {
      const message = getMessageMock()

      // Set up state with a user message
      const action: CopilotChatAction = {type: 'MESSAGE_ADDED', message}
      state = copilotChatReducer(state, action)

      manager.unselectPreviousChildMessage(message)

      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'MESSAGES_UNSELECT_PREVIOUS_MESSAGE'}))
    })
  })

  describe('retryUserChatMessage', () => {
    it('should retry the last user chat message and dispatch event to reset pointers', async () => {
      const thread = getThreadMock()
      const message = getMessageMock()

      // Set up state with a user message and a response
      let action: CopilotChatAction = {type: 'MESSAGES_UPDATED', messages: [message], state: 'loaded'}
      state = copilotChatReducer(state, action)

      const copilotResponse = {
        ...getMessageMock(),
        role: 'assistant',
        parentMessageID: message.id,
      } as CopilotChatMessage

      action = {type: 'MESSAGE_ADDED', message: copilotResponse}
      state = copilotChatReducer(state, action)

      chatService.createMessageStreaming = jest.fn().mockResolvedValue({
        response: {
          body: {
            getReader: () => new MockReader([]),
          },
        },
      })

      await manager.retryUserChatMessage(thread, copilotResponse)

      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'MESSAGES_UNSELECT_PREVIOUS_MESSAGE'}))
      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'MESSAGE_ADDED'}))
      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'WAITING_ON_COPILOT', loading: true}))
    })
  })

  describe('editUserChatMessage', () => {
    it('should send the new content of the edited user message', async () => {
      const thread = getThreadMock()
      const parentMessage = {
        ...getMessageMock(),
        id: '1',
        role: 'assistant',
      } as CopilotChatMessage

      const message = {
        ...getMessageMock(),
        id: '2',
        content: 'Old message',
        parentMessageID: parentMessage.id,
        parentMessageIndex: 0,
      }

      // Set up state with a user message and a response
      let action: CopilotChatAction = {type: 'MESSAGES_UPDATED', messages: [parentMessage], state: 'loaded'}
      state = copilotChatReducer(state, action)

      action = {type: 'MESSAGE_ADDED', message}
      state = copilotChatReducer(state, action)

      const copilotResponse = {
        ...getMessageMock(),
        id: '3',
        role: 'assistant',
        parentMessageID: message.id,
        parentMessageIndex: 1,
      } as CopilotChatMessage

      action = {type: 'MESSAGE_ADDED', message: copilotResponse}
      state = copilotChatReducer(state, action)

      chatService.createMessageStreaming = jest.fn().mockResolvedValue({
        response: {
          body: {
            getReader: () => new MockReader([]),
          },
        },
      })

      await manager.editUserChatMessage(thread, message, 'New message')

      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'MESSAGE_ADDED'}))
      expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({type: 'WAITING_ON_COPILOT', loading: true}))
    })
  })

  describe('#tryInferMessage', () => {
    it('does not infer message with no references', () => {
      const [wasInferred, newMessage] = manager.tryInferMessage([])

      expect(wasInferred).toBe(false)
      expect(newMessage).toBeUndefined()
    })

    it('infers "describe this image" when an image reference is present and message is empty', () => {
      const imageReference = getImageReferenceMock()
      let [wasInferred, newMessage] = manager.tryInferMessage([imageReference])

      expect(wasInferred).toBe(true)
      expect(newMessage).toBe('Describe this image')

      // also make sure it plays well in an array
      const repoInstructionsReference: RepoInstructionsReference = {
        type: 'repo-instructions',
        url: 'http://sample-repo-instructions.com',
      }

      ;[wasInferred, newMessage] = manager.tryInferMessage([imageReference, repoInstructionsReference])
      expect(wasInferred).toBe(true)
      expect(newMessage).toBe('Describe this image')
    })

    it('does not infer anything when a non image type is used', () => {
      // picking just any other reference type
      const repoInstructionsReference: RepoInstructionsReference = {
        type: 'repo-instructions',
        url: 'http://sample-repo-instructions.com',
      }
      const [wasInferred, newMessage] = manager.tryInferMessage([repoInstructionsReference])

      expect(wasInferred).toBe(false)
      expect(newMessage).toBeUndefined()
    })
  })

  describe('fetchMessages', () => {
    beforeEach(() => {
      // Clear feature flag mocks before each test
      mockClientEnv({featureFlags: []})
    })

    it('should load thread messages and update state', async () => {
      const threadId = '123'
      const messages = [getMessageMock(), getMessageMock()]
      const references = getReferencesMock()
      const thread = {...getThreadMock(), id: threadId, currentReferences: references}

      const listMessagesResponse = {
        ok: true,
        payload: {
          messages,
          thread,
        },
      }

      const listMessagesMock = jest.fn().mockResolvedValue(listMessagesResponse)
      chatService.listMessages = listMessagesMock

      const unblockFn = await manager.fetchMessages(threadId)
      unblockFn()

      expect(listMessagesMock).toHaveBeenCalledWith(threadId)
      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'MESSAGES_UPDATED',
          state: 'loading',
        }),
      )
      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'MESSAGES_UPDATED',
          messages,
          state: 'loaded',
        }),
      )
      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'REFERENCES_LOADED',
          references,
        }),
      )
    })

    it('should handle null threadID correctly', async () => {
      const listMessagesMock = jest.fn()
      chatService.listMessages = listMessagesMock

      const unblockFn = await manager.fetchMessages(null)
      unblockFn()

      expect(listMessagesMock).not.toHaveBeenCalled()
      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'MESSAGES_UPDATED',
          state: 'loaded',
        }),
      )
      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'REFERENCES_LOADED',
          references: [],
        }),
      )
    })

    it('should handle error responses correctly', async () => {
      const threadId = '123'
      chatService.listMessages = jest.fn().mockResolvedValue({
        ok: false,
        error: 'Some error occurred',
        status: 500,
      })

      const unblockFn = await manager.fetchMessages(threadId)
      unblockFn()

      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'MESSAGES_UPDATED',
          state: 'error',
        }),
      )
    })

    it('should handle 404 responses with missing org IDs correctly', async () => {
      const threadId = '123'
      chatService.listMessages = jest.fn().mockResolvedValue({
        ok: false,
        error: 'Not found',
        status: 404,
        payload: {
          missingOrgIds: ['org1', 'org2'],
        },
      })

      const unblockFn = await manager.fetchMessages(threadId)
      unblockFn()

      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'MESSAGES_UPDATED',
          state: 'error',
          notFound: true,
          missingOrgIds: ['org1', 'org2'],
        }),
      )
    })

    it('should resolve the reloading promise with true on successful load', async () => {
      const threadId = '123'
      const messages = [getMessageMock()]
      const thread = {...getThreadMock(), id: threadId}

      chatService.listMessages = jest.fn().mockResolvedValue({
        ok: true,
        payload: {
          messages,
          thread,
        },
      })

      // Create a spy for resolvePromise
      const resolvePromiseMock = jest.fn()

      // Simulate thread reload starting
      manager.startThreadReload()

      // Replace the resolvePromise method with our mock
      manager.resolvePromise = resolvePromiseMock

      const unblockFn = await manager.fetchMessages(threadId, true)
      unblockFn()

      // Check if our mock was called with true
      expect(resolvePromiseMock).toHaveBeenCalledWith(true)
    })

    it('should resolve the reloading promise with false on failed load', async () => {
      const threadId = '123'

      chatService.listMessages = jest.fn().mockResolvedValue({
        ok: false,
        error: 'Some error occurred',
        status: 500,
      })

      // Create a spy for resolvePromise
      const resolvePromiseMock = jest.fn()

      // Simulate thread reload starting
      manager.startThreadReload()

      // Replace the resolvePromise method with our mock
      manager.resolvePromise = resolvePromiseMock

      const unblockFn = await manager.fetchMessages(threadId, true)
      unblockFn()

      // Check if our mock was called with false
      expect(resolvePromiseMock).toHaveBeenCalledWith(false)
    })

    it('should call afterThreadReloadCallback with messages when provided', async () => {
      const threadId = '123'
      const messages = [getMessageMock(), getMessageMock()]
      const thread = {...getThreadMock(), id: threadId}

      chatService.listMessages = jest.fn().mockResolvedValue({
        ok: true,
        payload: {
          messages,
          thread,
        },
      })

      // Set up a mock callback
      const mockCallback = jest.fn()

      // Access the manager instance directly and set the property
      // @ts-expect-error: accessing private property for testing
      manager.afterThreadReloadCallback = mockCallback

      const unblockFn = await manager.fetchMessages(threadId, true)
      unblockFn()

      expect(mockCallback).toHaveBeenCalledWith(messages)
    })

    it('should retry fetching messages when expectNewMessages is true and no new messages', async () => {
      const threadId = '123'
      const messages = [getMessageMock()]
      const thread = {...getThreadMock(), id: threadId}

      // Mock state to have the same number of messages as the response
      state.messages = [getMessageMock()]

      const listMessagesMock = jest.fn().mockImplementation(() => {
        return {
          ok: true,
          payload: {
            messages,
            thread,
          },
        }
      })
      chatService.listMessages = listMessagesMock

      const unblockFn = await manager.fetchMessages(threadId, true, true)
      unblockFn()

      // Should have called listMessages twice - first attempt plus retry
      expect(listMessagesMock).toHaveBeenCalledTimes(2)
    })

    it('should handle thread ID changing during reload', async () => {
      const threadId = '123'
      const newThreadId = '456'
      const messages = [getMessageMock()]
      const thread = {...getThreadMock(), id: threadId}

      chatService.listMessages = jest.fn().mockResolvedValue({
        ok: true,
        payload: {
          messages,
          thread,
        },
      })

      // Create a spy for resolvePromise
      const resolvePromiseMock = jest.fn()

      // Simulate thread reload starting
      manager.startThreadReload()

      // Replace the resolvePromise method with our mock
      manager.resolvePromise = resolvePromiseMock

      // Start fetching messages for threadId
      const fetchPromise = manager.fetchMessages(threadId, true)

      // Change the thread ID being fetched while the first fetch is in progress
      // @ts-expect-error: accessing private property for testing
      manager.fetchingThreadID = newThreadId

      const unblockFn = await fetchPromise
      unblockFn()

      // The resolvePromise should be called with false since the thread ID changed
      expect(resolvePromiseMock).toHaveBeenCalledWith(false)
    })

    describe('plugin integration', () => {
      it('should select a matching plugin when found', async () => {
        const threadId = '123'
        const messages = [getMessageMock()]
        const references = getReferencesMock()
        const thread = {...getThreadMock(), id: threadId, currentReferences: references}

        chatService.listMessages = jest.fn().mockResolvedValue({
          ok: true,
          payload: {
            messages,
            thread,
          },
        })

        const mockPlugin = {
          id: 'test-plugin',
          displayName: 'Test Plugin',
          matchThread: jest.fn().mockReturnValue(true),
          overrideCreateMessageOptions: jest.fn(),
        }

        // Set up the manager with our mock plugin
        manager = new CopilotChatManager(dispatch, 'apiURL', [], () => state, undefined, chatService, false, [
          mockPlugin,
        ])

        const unblockFn = await manager.fetchMessages(threadId)
        unblockFn()

        expect(mockPlugin.matchThread).toHaveBeenCalledWith(threadId, messages, references)
        expect(dispatch).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'SELECT_PLUGIN',
            plugin: 'test-plugin',
          }),
        )
      })

      it('should clear plugin selection when no plugin matches', async () => {
        const threadId = '123'
        const messages = [getMessageMock()]
        const references = getReferencesMock()
        const thread = {...getThreadMock(), id: threadId, currentReferences: references}

        chatService.listMessages = jest.fn().mockResolvedValue({
          ok: true,
          payload: {
            messages,
            thread,
          },
        })

        // Add an active plugin to the state
        state = {...state, activePlugin: 'current-plugin'}

        const mockPlugin = {
          id: 'test-plugin',
          displayName: 'Test Plugin',
          matchThread: jest.fn().mockReturnValue(false),
          overrideCreateMessageOptions: jest.fn(),
        }

        // Set up the manager with our mock plugin
        manager = new CopilotChatManager(dispatch, 'apiURL', [], () => state, undefined, chatService, false, [
          mockPlugin,
        ])

        const unblockFn = await manager.fetchMessages(threadId)
        unblockFn()

        expect(mockPlugin.matchThread).toHaveBeenCalledWith(threadId, messages, references)
        expect(dispatch).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'SELECT_PLUGIN',
            plugin: undefined,
          }),
        )
      })

      it('should not change plugin if current active plugin matches thread', async () => {
        const threadId = '123'
        const messages = [getMessageMock()]
        const references = getReferencesMock()
        const thread = {...getThreadMock(), id: threadId, currentReferences: references}

        chatService.listMessages = jest.fn().mockResolvedValue({
          ok: true,
          payload: {
            messages,
            thread,
          },
        })

        // Add an active plugin to the state
        state = {...state, activePlugin: 'test-plugin'}

        const mockPlugin = {
          id: 'test-plugin',
          displayName: 'Test Plugin',
          matchThread: jest.fn().mockReturnValue(true),
          overrideCreateMessageOptions: jest.fn(),
        }

        // Set up the manager with our mock plugin
        manager = new CopilotChatManager(dispatch, 'apiURL', [], () => state, undefined, chatService, false, [
          mockPlugin,
        ])

        const unblockFn = await manager.fetchMessages(threadId)
        unblockFn()

        expect(mockPlugin.matchThread).toHaveBeenCalledWith(threadId, messages, references)
        // Should not dispatch SELECT_PLUGIN since the plugin is already active
        expect(dispatch).not.toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'SELECT_PLUGIN',
          }),
        )
      })
    })
  })

  describe('fetchSharedThreadMessages', () => {
    const gpt: CopilotChatModel = {...getModelMock(), id: 'gpt-4o'}
    const claude: CopilotChatModel = {...getModelMock(), id: 'claude-3.5-sonnet'}
    const gemini: CopilotChatModel = {...getModelMock(), id: 'gemini-2.0-flash'}
    const models: CopilotChatModel[] = [gpt, claude, gemini]

    beforeEach(() => {
      manager.fetchModels = jest.fn().mockImplementation(() => {
        state = {
          ...state,
          availableModels: models,
        }
      })
    })

    it('should load shared thread messages and update state', async () => {
      const threadId = '123'
      const messages = [getMessageMock(), getMessageMock()]

      const listSharedThreadMessagesMock = jest.fn().mockResolvedValue({
        ok: true,
        status: 200,
        payload: {
          messages,
        },
      })
      chatService.listSharedThreadMessages = listSharedThreadMessagesMock

      await manager.fetchSharedThreadMessages(threadId)

      expect(listSharedThreadMessagesMock).toHaveBeenCalledWith(threadId)
      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'MESSAGES_UPDATED',
          state: 'loading',
        }),
      )
      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'FETCH_SHARED_THREAD_MESSAGES',
          ok: true,
          status: 200,
        }),
      )
      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'MESSAGES_UPDATED',
          messages,
          state: 'loaded',
        }),
      )
      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'REFERENCES_LOADED',
          references: [],
        }),
      )
    })

    it('should handle null threadID by doing nothing', async () => {
      const listSharedThreadMessagesMock = jest.fn()
      chatService.listSharedThreadMessages = listSharedThreadMessagesMock

      await manager.fetchSharedThreadMessages(null)

      expect(listSharedThreadMessagesMock).not.toHaveBeenCalled()
      expect(dispatch).not.toHaveBeenCalled()
    })

    it('should handle error responses correctly', async () => {
      const threadId = '123'
      chatService.listSharedThreadMessages = jest.fn().mockResolvedValue({
        ok: false,
        status: 404,
        error: 'Some error occurred',
      })

      await manager.fetchSharedThreadMessages(threadId)

      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'FETCH_SHARED_THREAD_MESSAGES',
          ok: false,
          status: 404,
        }),
      )
      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'MESSAGES_UPDATED',
          state: 'error',
        }),
      )
    })

    it('selects the model used in the most recent message', async () => {
      const thread: CopilotChatThread = getThreadMock()
      const messages: CopilotChatMessage[] = [
        {...getMessageMock()},
        {...getMessageMock(), model: gpt.id},
        {...getMessageMock()},
        {...getMessageMock(), model: claude.id},
      ]

      chatService.listSharedThreadMessages = jest.fn().mockResolvedValue({
        ok: true,
        status: 200,
        payload: {
          thread,
          messages,
        },
      })

      const selectModelMock = jest.fn()
      manager.selectModel = selectModelMock

      await manager.fetchSharedThreadMessages(thread.id)

      expect(selectModelMock).toHaveBeenCalledTimes(1)
      expect(selectModelMock).toHaveBeenCalledWith(claude)
    })
  })

  describe('continueSharedThread', () => {
    it('should duplicate a thread and its messages and update state', async () => {
      const threadId = '123'
      const messages = [getMessageMock(), getMessageMock()]
      const newThread = {...getThreadMock(), id: '456'}

      const continueSharedThreadMock = jest.fn().mockResolvedValue({
        ok: true,
        status: 200,
        payload: {
          thread: newThread,
          messages,
        },
      })
      chatService.continueSharedThread = continueSharedThreadMock

      await manager.continueSharedThread(threadId)

      expect(continueSharedThreadMock).toHaveBeenCalledWith(threadId)
      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'MESSAGES_UPDATED',
          state: 'loading',
        }),
      )
      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'THREAD_CONTINUED',
          thread: newThread,
        }),
      )
      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'MESSAGES_UPDATED',
          messages,
          state: 'loaded',
        }),
      )
    })

    it('should dispatch an event and not make a CAPI request if we have no thread ID', async () => {
      const continueSharedThreadMock = jest.fn()
      chatService.continueSharedThread = continueSharedThreadMock

      state = {
        ...state,
        fetchSharedThreads: undefined,
      }

      await manager.continueSharedThread(null)

      expect(continueSharedThreadMock).not.toHaveBeenCalled()
      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'THREAD_CONTINUED_FAILED',
        }),
      )
    })
  })

  describe('removeReferences', () => {
    it('should remove references from the state', () => {
      const references = getReferencesMock()

      manager.removeReferences(references)

      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'REMOVE_REFERENCES',
          references,
        }),
      )
    })

    it('should remove single references from the state', () => {
      const references = getReferencesMock()

      manager.removeReference(references[0])

      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'REMOVE_REFERENCES',
          references: [references[0]],
        }),
      )
    })

    it('aborts signals for uploadable files on remove', () => {
      const name = 'name.png'
      const blob = new Blob(['Some test content'], {type: 'image/png'})
      const file: File = new File([blob], name, {
        type: 'image/png',
        lastModified: Date.now(),
      })

      jest.spyOn(copilotFeatureFlags, 'dotcomChatFileUpload', 'get').mockReturnValue(true)
      const result = CopilotImageAttacher.makeImageReference(file, 'some-thread-id')

      expect(result.attachment).toBeInstanceOf(UploadableFileAttachment)
      const uploadable = result.attachment as UploadableFileAttachment
      expect(uploadable.abortController.signal.aborted).toBeFalsy()

      manager.removeReference(result)

      expect(uploadable.abortController.signal.aborted).toBeTruthy()
    })
  })

  describe('clearCurrentReferences', () => {
    it('should clear references from the state', () => {
      manager.clearCurrentReferences()

      expect(dispatch).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'CLEAR_CURRENT_REFERENCES',
        }),
      )
    })

    it('aborts signals for uploadable files on remove', () => {
      const name = 'name.png'
      const blob = new Blob(['Some test content'], {type: 'image/png'})
      const file: File = new File([blob], name, {
        type: 'image/png',
        lastModified: Date.now(),
      })

      jest.spyOn(copilotFeatureFlags, 'dotcomChatFileUpload', 'get').mockReturnValue(true)
      const result = CopilotImageAttacher.makeImageReference(file, 'some-thread-id')
      expect(result.attachment).toBeInstanceOf(UploadableFileAttachment)
      const uploadable = result.attachment as UploadableFileAttachment
      expect(uploadable.abortController.signal.aborted).toBeFalsy()

      state.currentReferences = [result]

      // First make sure that clearCurrentReferences understands to skip images sometimes
      manager.clearCurrentReferences(['image'])
      expect(uploadable.abortController.signal.aborted).toBeFalsy()

      // Verify calling clear without arguments aborts the signal
      manager.clearCurrentReferences()
      expect(uploadable.abortController.signal.aborted).toBeTruthy()
    })
  })
})
