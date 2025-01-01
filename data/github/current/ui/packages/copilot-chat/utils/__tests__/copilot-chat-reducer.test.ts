import {getCustomCopilotMock} from '@github-ui/custom-copilots/test-utils/mock-data'
import {sendEvent} from '@github-ui/hydro-analytics'

import {
  getDocsetMock,
  getImageReferenceMock,
  getMessageMock,
  getMessageStreamingResponseMock,
  getModelMock,
  getReducerStateMock,
  getRepositoryMock,
  getRepositoryReferenceMock,
  getSnippetReferenceMock,
  getSymbolReferenceMock,
  getThreadMock,
} from '../../test-utils/mock-data'
import type {CopilotChatAction} from '../copilot-chat-reducer'
import {copilotChatReducer} from '../copilot-chat-reducer'
import {
  addMessageToHierarchy,
  constructMessagesHierarchy,
  getActiveMessages,
  selectActiveMessage,
  unselectPreviousChild,
} from '../copilot-chat-subthreading-helpers-unstable'
import type {ChatError, CopilotChatMessage, CustomCopilot} from '../copilot-chat-types'
import {copilotFeatureFlags} from '../copilot-feature-flags'

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    ...jest.requireActual('@github-ui/hydro-analytics'),
    sendEvent: jest.fn((type: string, context?: Record<string, string | number | boolean | null | undefined>) => {
      // try to catch logging messages
      if (context?.content !== undefined) {
        throw new Error('Content should not be logged. Are you logging a message?')
      }
      // try to catch logging references
      if (context?.repoOwner || context?.ownerLogin) {
        throw new Error('References should not be logged. Are you logging a reference?')
      }
      // try to catch logging threads
      if (context?.currentReferences) {
        throw new Error('Threads should not be logged. Are you logging a thread?')
      }
    }),
  }
})

jest.mock('../copilot-chat-subthreading-helpers-unstable', () => ({
  addMessageToHierarchy: jest.fn((messages, newMessage) => [...messages, newMessage]),
  constructMessagesHierarchy: jest.fn(messages => messages),
  selectActiveMessage: jest.fn(messages => messages),
  unselectPreviousChild: jest.fn(messages => messages),
  getActiveMessages: jest.fn(messages => messages),
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  updateCompletedMessageParent: jest.fn((messages, _newMessage) => messages),
}))

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))

beforeEach(() => {
  jest.clearAllMocks()
})

test('Slash commands error', () => {
  const action: CopilotChatAction = {type: 'SLASH_COMMANDS_ERROR'}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.slashCommandLoading.state).toBe('error')
  expect(sendEvent).toHaveBeenCalledWith('copilot.slash_commands_error')
})

test('Slash commands loaded', () => {
  const action: CopilotChatAction = {type: 'SLASH_COMMANDS_LOADED'}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.slashCommandLoading.state).toBe('loaded')
  expect(sendEvent).toHaveBeenCalledWith('copilot.slash_commands_loaded')
})

test('Slash commands loading', () => {
  const action: CopilotChatAction = {type: 'SLASH_COMMANDS_LOADING'}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.slashCommandLoading.state).toBe('loading')
})

test('Open copilot chat', () => {
  const action: CopilotChatAction = {type: 'OPEN_COPILOT_CHAT', source: 'test'}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.chatIsOpen).toBe(true)
  expect(sendEvent).toHaveBeenCalledWith('copilot.open_copilot_chat', {source: 'test'})
})

test('Close copilot chat', () => {
  const action: CopilotChatAction = {type: 'CLOSE_COPILOT_CHAT'}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.chatIsOpen).toBe(false)
  expect(sendEvent).toHaveBeenCalledWith('copilot.close_copilot_chat')
})

test('Adds a thread', () => {
  const thread = getThreadMock()
  const action: CopilotChatAction = {type: 'THREAD_CREATED', thread}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.threads.size).toBe(1)
  expect(sendEvent).toHaveBeenCalledWith('copilot.thread_created', {
    count: 1,
    createdAt: '"2020-01-01T00:00:00Z"',
    currentReferenceCount: '0',
    id: '"0"',
    mode: 'assistive',
    updatedAt: '"2020-01-01T00:00:00Z"',
  })
})

test('Adds a thread with a custom copilot id', () => {
  const thread = {...getThreadMock(), customCopilotID: 28}
  const action: CopilotChatAction = {type: 'THREAD_CREATED', thread}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.threads.size).toBe(1)
  expect(sendEvent).toHaveBeenCalledWith('copilot.thread_created', {
    count: 1,
    createdAt: '"2020-01-01T00:00:00Z"',
    currentReferenceCount: '0',
    id: '"0"',
    mode: 'assistive',
    updatedAt: '"2020-01-01T00:00:00Z"',
  })
  expect(state.threads.get(thread.id)?.customCopilotID).toBe(28)
})

test('Clear thread', () => {
  const action: CopilotChatAction = {type: 'CLEAR_THREAD', threadID: '0'}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.threads.size).toBe(0)
  expect(sendEvent).toHaveBeenCalledWith('copilot.clear_thread')
})

test('Dismiss "attach knowledge base here" popover', () => {
  const action: CopilotChatAction = {type: 'DISMISS_ATTACH_KNOWLEDGE_BASE_HERE_POPOVER'}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.renderAttachKnowledgeBaseHerePopover).toBe(false)
  expect(sendEvent).toHaveBeenCalledWith('copilot.dismiss_attach_knowledge_base_here_popover')
})

test('Update personal instructions', () => {
  const action: CopilotChatAction = {type: 'SET_PERSONAL_INSTRUCTIONS', personalInstructions: 'new instructions'}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.personalInstructions).toEqual('new instructions')
})

test('Dismiss "knowledge base attached to chat" popover', () => {
  const action: CopilotChatAction = {type: 'DISMISS_KNOWLEDGE_BASE_ATTACHED_TO_CHAT_POPOVER'}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.renderKnowledgeBaseAttachedToChatPopover).toBe(false)
  expect(sendEvent).toHaveBeenCalledWith('copilot.dismiss_knowledge_base_attached_to_chat_popover')
})

describe('Messages updated', () => {
  it('sends updated messages event and constructs message hierarchy', () => {
    const action: CopilotChatAction = {type: 'MESSAGES_UPDATED', messages: [getMessageMock()], state: 'loaded'}
    const state = copilotChatReducer(getReducerStateMock(), action)
    expect(state.messages.length).toBe(1)
    expect(constructMessagesHierarchy).toHaveBeenCalled()
  })
})

test('Waiting on copilot', () => {
  const action: CopilotChatAction = {type: 'WAITING_ON_COPILOT', loading: true}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.isWaitingOnCopilot).toBe(true)
})

test('Select thread', () => {
  const action: CopilotChatAction = {type: 'SELECT_THREAD', thread: getThreadMock()}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.selectedThreadID).toBe('0')
  expect(sendEvent).toHaveBeenCalledWith('copilot.select_thread', {
    threadID: '0',
    mode: 'assistive',
  })
  expect(state.currentTopic).toBeDefined()
})

test('Select thread clear topic', () => {
  const action: CopilotChatAction = {type: 'SELECT_THREAD', thread: null, clearTopic: true}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.selectedThreadID).toBeNull()
  expect(sendEvent).toHaveBeenCalledWith('copilot.select_thread', {
    threadID: undefined,
    mode: 'assistive',
  })
  expect(state.currentTopic).toBeUndefined()
})

test('Handle event start', () => {
  const action: CopilotChatAction = {type: 'HANDLE_EVENT_START', references: [getRepositoryReferenceMock()]}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.currentReferences.length).toBe(1)
  expect(sendEvent).toHaveBeenCalledWith('copilot.handle_event_start')
})

test('Threads loading', () => {
  const action: CopilotChatAction = {type: 'THREADS_LOADING'}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.threadsLoading.state).toBe('loading')
})

test('Threads loaded', () => {
  const action: CopilotChatAction = {type: 'THREADS_LOADED', threads: [getThreadMock()]}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.threadsLoading.state).toBe('loaded')
  expect(sendEvent).toHaveBeenCalledWith('copilot.threads_loaded', {count: 1, mode: 'assistive'})
})

test('Threads loading error', () => {
  const action: CopilotChatAction = {type: 'THREADS_LOADING_ERROR', message: 'error', status: 403}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.threadsLoading.state).toBe('error')
  expect(sendEvent).toHaveBeenCalledWith('copilot.threads_loading_error', {error: 'error'})
})

test('Delete thread', () => {
  const thread = getThreadMock()
  const threads = new Map()
  threads.set(thread.id, thread)
  const action: CopilotChatAction = {type: 'DELETE_THREAD', thread}
  const state = copilotChatReducer({...getReducerStateMock(), threads}, action)
  expect(state.threads.size).toBe(0)
  expect(sendEvent).toHaveBeenCalledWith('copilot.thread_deleted', {
    count: 0,
    createdAt: '"2020-01-01T00:00:00Z"',
    currentReferenceCount: '0',
    id: '"0"',
    mode: 'assistive',
    updatedAt: '"2020-01-01T00:00:00Z"',
  })
})

test('Delete all threads', () => {
  const thread1 = getThreadMock()
  const thread2 = getThreadMock()
  thread2.id = '1'
  const threadsMap = new Map()
  threadsMap.set(thread1.id, thread1)
  threadsMap.set(thread2.id, thread2)
  const threads = [thread1, thread2]
  const action: CopilotChatAction = {type: 'DELETE_ALL_THREADS_KEEP_SELECTION', threads}
  const state = copilotChatReducer({...getReducerStateMock(), threads: threadsMap}, action)
  expect(state.threads.size).toBe(0)
  expect(sendEvent).toHaveBeenNthCalledWith(1, 'copilot.thread_deleted', {
    count: 1,
    createdAt: '"2020-01-01T00:00:00Z"',
    currentReferenceCount: '0',
    id: '"0"',
    updatedAt: '"2020-01-01T00:00:00Z"',
  })
  expect(sendEvent).toHaveBeenNthCalledWith(2, 'copilot.thread_deleted', {
    count: 0,
    createdAt: '"2020-01-01T00:00:00Z"',
    currentReferenceCount: '0',
    id: '"1"',
    updatedAt: '"2020-01-01T00:00:00Z"',
  })
})

test('Delete thread error', () => {
  const action: CopilotChatAction = {type: 'DELETE_THREAD_ERROR', thread: getThreadMock(), error: 'error'}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.threadsLoading.error).toBe('error')
  expect(sendEvent).toHaveBeenCalledWith('copilot.delete_thread_error', {
    createdAt: '"2020-01-01T00:00:00Z"',
    currentReferenceCount: '0',
    id: '"0"',
    updatedAt: '"2020-01-01T00:00:00Z"',
    error: 'error',
  })
})

test('Delete all threads error', () => {
  const thread1 = getThreadMock()
  const thread2 = getThreadMock()
  thread2.id = '1'
  const threads = [thread1, thread2]
  const action: CopilotChatAction = {type: 'DELETE_ALL_THREADS_ERROR', threads, error: 'error'}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.threadsLoading.error).toBe('error')
  expect(sendEvent).toHaveBeenNthCalledWith(1, 'copilot.delete_thread_error', {
    createdAt: '"2020-01-01T00:00:00Z"',
    currentReferenceCount: '0',
    id: '"0"',
    updatedAt: '"2020-01-01T00:00:00Z"',
    error: 'error',
  })
  expect(sendEvent).toHaveBeenNthCalledWith(2, 'copilot.delete_thread_error', {
    createdAt: '"2020-01-01T00:00:00Z"',
    currentReferenceCount: '0',
    id: '"1"',
    updatedAt: '"2020-01-01T00:00:00Z"',
    error: 'error',
  })
})

describe('Message added', () => {
  it('Adds message to hierarchy', () => {
    const message = getMessageMock()
    const action: CopilotChatAction = {type: 'MESSAGE_ADDED', message}
    const state = copilotChatReducer(getReducerStateMock(), action)
    expect(state.messages.length).toBe(1)
    expect(sendEvent).toHaveBeenCalledWith('copilot.message_added', {
      count: 1,
      id: '"0"',
      role: '"user"',
      createdAt: '"2020-01-01T00:00:00Z"',
      threadID: '"0"',
      referenceCount: '0',
      repoHasCustomInstructions: false,
      usedRepoCustomInstructions: false,
    })

    expect(addMessageToHierarchy).toHaveBeenCalled()
  })
})

test('Thread updated', () => {
  const thread = getThreadMock()
  const createAction: CopilotChatAction = {type: 'THREAD_CREATED', thread}
  let state = copilotChatReducer(getReducerStateMock(), createAction)
  expect(state.threads.size).toBe(1)

  const newName = `${thread.name}+updated`
  const updateAction: CopilotChatAction = {type: 'THREAD_UPDATED', thread: {id: thread.id, name: newName}}
  state = copilotChatReducer(state, updateAction)
  expect(state.threads.size).toBe(1)
  expect(state.threads.get(thread.id)?.name).toEqual(newName)
})

test('References loaded', () => {
  const action: CopilotChatAction = {type: 'REFERENCES_LOADED', references: [getRepositoryReferenceMock()]}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.currentReferences.length).toBe(1)
  expect(sendEvent).toHaveBeenCalledWith('copilot.references_loaded', {count: 1})
})

test('Adds a reference', () => {
  const reference = getRepositoryReferenceMock()
  const action: CopilotChatAction = {type: 'ADD_REFERENCE', reference, source: 'source'}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.currentReferences.length).toBe(1)
  expect(sendEvent).toHaveBeenCalledWith('copilot.add_reference', {
    count: 1,
    source: 'source',
    type: '"repository"',
  })
})

test('Removes a reference', () => {
  const reference = getRepositoryReferenceMock()
  const action: CopilotChatAction = {type: 'REMOVE_REFERENCES', references: [reference]}
  const state = copilotChatReducer({...getReducerStateMock(), currentReferences: [reference]}, action)
  expect(state.currentReferences.length).toBe(0)
  expect(sendEvent).toHaveBeenCalledWith('copilot.remove_reference', {
    count: 0,
  })
})

test('Removes multiple references', () => {
  const references = [getRepositoryReferenceMock(), getSnippetReferenceMock(), getSymbolReferenceMock()]
  const action: CopilotChatAction = {type: 'REMOVE_REFERENCES', references: references.slice(0, 2)}
  const state = copilotChatReducer({...getReducerStateMock(), currentReferences: references}, action)
  expect(state.currentReferences.length).toBe(1)
  expect(sendEvent).toHaveBeenCalledWith('copilot.remove_reference', {
    count: 1,
  })
})

test('Current topic updated', () => {
  const action: CopilotChatAction = {type: 'CURRENT_TOPIC_UPDATED', topic: getRepositoryMock(), state: 'loaded'}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.currentTopic).toStrictEqual(getRepositoryMock())
  expect(sendEvent).toHaveBeenCalledWith('copilot.current_topic_updated', {
    mode: 'assistive',
    type: 'repository',
  })
})

test('Message streaming started', () => {
  const action: CopilotChatAction = {type: 'MESSAGE_STREAMING_STARTED', message: getMessageMock()}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.isWaitingOnCopilot).toBe(true)
  expect(state.streamingMessage).toEqual(getMessageMock())
})

test('Message streaming token added', () => {
  const action: CopilotChatAction = {type: 'MESSAGE_STREAMING_TOKEN_ADDED', token: 'token'}
  const state = copilotChatReducer({...getReducerStateMock(), streamingMessage: getMessageMock()}, action)
  expect(state.streamingMessage?.content).toBe('contenttoken')
})

describe('Message streaming complete', () => {
  it('adds completed streaming message to the state and hierarchy', () => {
    const message = {
      ...getMessageMock(),
      id: 'randomID',
      role: 'user',
    } as CopilotChatMessage
    const streamingMessage = {
      ...getMessageMock(),
      id: '1',
      role: 'assistant',
      parentMessageID: '0',
    } as CopilotChatMessage
    const streamingResponse = {
      ...getMessageStreamingResponseMock(),
      parentMessageID: '0',
    }

    const action: CopilotChatAction = {
      type: 'MESSAGE_STREAMING_COMPLETED',
      messageResponse: streamingResponse,
      timings: {startTime: 0, endTime: 0},
    }
    const state = copilotChatReducer({...getReducerStateMock(), messages: [message], streamingMessage}, action)
    expect(state.streamingMessage).toBeNull()
    expect(state.messages.length).toBe(2)
    expect(sendEvent).toHaveBeenCalledWith('copilot.message_streaming_completed', {
      count: 2,
      id: '"0"',
      intent: '"conversation"',
      role: '"assistant"',
      createdAt: '"2020-01-01T00:00:00Z"',
      threadID: '"0"',
      referenceCount: '0',
      totalTime: 0,
      mode: 'assistive',
      model: 'gpt-4.1',
    })
    expect(state.messages[1]?.id).toEqual('0')
    expect(addMessageToHierarchy).toHaveBeenCalled()
  })
})

test('Message streaming failed', () => {
  const action: CopilotChatAction = {type: 'MESSAGE_STREAMING_FAILED', timings: {startTime: 0, endTime: 1000}}
  const state = copilotChatReducer({...getReducerStateMock(), streamingMessage: getMessageMock()}, action)
  expect(state.streamingMessage).toBeNull()
  expect(sendEvent).toHaveBeenCalledWith('copilot.message_streaming_failed', {
    createdAt: '"2020-01-01T00:00:00Z"',
    id: '"0"',
    mode: 'assistive',
    model: 'gpt-4.1',
    referenceCount: '0',
    role: '"user"',
    threadID: '"0"',
    totalTime: 1000,
  })
})

test('Message streaming stopped', () => {
  const message = getMessageMock()
  const action: CopilotChatAction = {type: 'MESSAGE_STREAMING_STOPPED', timings: {startTime: 0, endTime: 1000}}
  ;(getActiveMessages as jest.Mock).mockReturnValueOnce([message])
  const state = copilotChatReducer({...getReducerStateMock(), streamingMessage: message}, action)
  expect(state.isWaitingOnCopilot).toBeFalsy()
  expect(state.streamingMessage).toBeNull()
  expect(state.messages.length).toBe(1)
  expect(sendEvent).toHaveBeenCalledWith('copilot.message_streaming_stopped', {
    count: 1,
    id: '"0"',
    role: '"user"',
    createdAt: '"2020-01-01T00:00:00Z"',
    threadID: '"0"',
    referenceCount: '0',
    interrupted: 'true',
    mode: 'assistive',
    model: 'gpt-4.1',
    totalTime: 1000,
  })

  expect(addMessageToHierarchy).toHaveBeenCalled()
})

test('Select reference', () => {
  const action: CopilotChatAction = {type: 'SELECT_REFERENCE', reference: getRepositoryReferenceMock()}
  const state = copilotChatReducer(getReducerStateMock(), action)
  expect(state.selectedReference).toStrictEqual(getRepositoryReferenceMock())
  expect(sendEvent).toHaveBeenCalledWith('copilot.select_reference', {
    type: '"repository"',
  })
})

describe('Clear references', () => {
  test('Clears all references', () => {
    const action: CopilotChatAction = {type: 'CLEAR_CURRENT_REFERENCES'}
    const stateWithReferences = {
      ...getReducerStateMock(),
      currentReferences: [getRepositoryReferenceMock(), getSnippetReferenceMock()],
    }
    const state = copilotChatReducer(stateWithReferences, action)
    expect(state.currentReferences.length).toBe(0)
  })

  test('leaves knowledge base references when FF is enabled', () => {
    const action: CopilotChatAction = {type: 'CLEAR_CURRENT_REFERENCES', keepTypes: ['docset']}
    const docsetReference = {...getDocsetMock(), type: 'docset' as const}
    const stateWithReferences = {
      ...getReducerStateMock(),
      currentReferences: [getRepositoryReferenceMock(), getSnippetReferenceMock(), docsetReference],
    }

    const state = copilotChatReducer(stateWithReferences, action)
    expect(state.currentReferences.length).toBe(1)
    expect(state.currentReferences[0]).toStrictEqual(docsetReference)
  })

  test('leaves image references when image is passed to shouldNotClear and ff enabled', () => {
    jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(true)
    const imageReference = getImageReferenceMock()
    const action: CopilotChatAction = {type: 'CLEAR_CURRENT_REFERENCES', keepTypes: ['image']}
    const stateWithReferences = {
      ...getReducerStateMock(),
      currentReferences: [getRepositoryReferenceMock(), getSnippetReferenceMock(), imageReference],
    }

    const state = copilotChatReducer(stateWithReferences, action)
    expect(state.currentReferences.length).toBe(1)
    expect(state.currentReferences[0]).toStrictEqual(imageReference)
    expect(sendEvent).toHaveBeenCalledWith('copilot.clear_current_references')
  })

  test('removes image references when image is passed to shouldNotClear and ff disabled', () => {
    jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(false)
    const imageReference = getImageReferenceMock()
    const action: CopilotChatAction = {type: 'CLEAR_CURRENT_REFERENCES', keepTypes: ['image']}
    const stateWithReferences = {
      ...getReducerStateMock(),
      currentReferences: [getRepositoryReferenceMock(), getSnippetReferenceMock(), imageReference],
    }

    const state = copilotChatReducer(stateWithReferences, action)
    expect(state.currentReferences.length).toBe(0)
    expect(sendEvent).toHaveBeenCalledWith('copilot.clear_current_references')
  })

  test('removes image references ff enabled', () => {
    jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(true)
    const imageReference = getImageReferenceMock()
    const action: CopilotChatAction = {type: 'CLEAR_CURRENT_REFERENCES'}
    const stateWithReferences = {
      ...getReducerStateMock(),
      currentReferences: [getRepositoryReferenceMock(), getSnippetReferenceMock(), imageReference],
    }

    const state = copilotChatReducer(stateWithReferences, action)
    expect(state.currentReferences.length).toBe(0)
    expect(sendEvent).toHaveBeenCalledWith('copilot.clear_current_references')
  })

  test('removes image references ff disabled', () => {
    jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(false)
    const imageReference = getImageReferenceMock()
    const action: CopilotChatAction = {type: 'CLEAR_CURRENT_REFERENCES'}
    const stateWithReferences = {
      ...getReducerStateMock(),
      currentReferences: [getRepositoryReferenceMock(), getSnippetReferenceMock(), imageReference],
    }

    const state = copilotChatReducer(stateWithReferences, action)
    expect(state.currentReferences.length).toBe(0)
    expect(sendEvent).toHaveBeenCalledWith('copilot.clear_current_references')
  })
})

test('Select model', () => {
  const action: CopilotChatAction = {type: 'SELECT_MODEL', model: getModelMock()}
  const state = copilotChatReducer({...getReducerStateMock(), mode: 'immersive'}, action)
  expect(state.model).toStrictEqual(getModelMock())
  expect(sendEvent).toHaveBeenCalledWith('copilot.select_model', {
    mode: 'immersive',
    model: 'GPT-4.1',
  })
})

test('Load models updates the active model if the loaded models have a matching model', () => {
  const newModel = getModelMock()
  // Verify current default behavior. If you see this test fail because this has been updated, you can update the test to match a different string update.
  expect(newModel.capabilities.supports.vision).toBe(undefined)
  newModel.capabilities.supports.vision = true
  const action: CopilotChatAction = {type: 'MODELS_LOADED', models: [newModel]}
  const state = copilotChatReducer({...getReducerStateMock(), model: getModelMock()}, action)
  expect(state.model).toStrictEqual(newModel)
  expect(state.model.capabilities.supports.vision).toBe(true)
})

test('Clear error messages', () => {
  const error = {} as ChatError
  const errorMessage = {...getMessageMock(), error}
  const action: CopilotChatAction = {type: 'MESSAGES_CLEAR_LAST_ERROR'}
  const state = copilotChatReducer({...getReducerStateMock(), messages: [errorMessage]}, action)
  expect(state.messages[0]).toBeUndefined()
  expect(state.messages.length).toBe(0)
  expect(state.streamingMessage).toBeNull()
})

test('Clear interrupted messages', () => {
  const interruptedMessage = {...getMessageMock(), interrupted: true}
  const action: CopilotChatAction = {type: 'MESSAGES_CLEAR_LAST_ERROR'}
  ;(getActiveMessages as jest.Mock).mockReturnValueOnce([interruptedMessage])
  const state = copilotChatReducer({...getReducerStateMock(), messages: [interruptedMessage]}, action)
  expect(state.messages.length).toBe(0)
  expect(state.streamingMessage).toBeNull()
})

test('Dismiss ambient errors', () => {
  const action: CopilotChatAction = {type: 'DISMISS_AMBIENT_ERROR'}
  const state = copilotChatReducer({...getReducerStateMock(), ambientError: {message: 'test'}}, action)
  expect(state.ambientError).toBeNull()
})

test('Add ambient error', () => {
  const action: CopilotChatAction = {type: 'ADD_AMBIENT_ERROR', message: 'test message'}
  const state = copilotChatReducer({...getReducerStateMock()}, action)
  expect(state.ambientError).not.toBeNull()
  expect(state.ambientError?.message).toBe('test message')
})

test('Set selected message', () => {
  const message = getMessageMock()
  const child1 = {
    ...getMessageMock(),
    id: '1',
    role: 'assistant',
    parentMessageID: message.id,
  } as CopilotChatMessage

  const child2 = {
    ...getMessageMock(),
    id: '2',
    role: 'assistant',
    parentMessageID: message.id,
  } as CopilotChatMessage

  const action: CopilotChatAction = {
    type: 'MESSAGES_SET_SELECTED_MESSAGE',
    message: child2,
  }
  const state = copilotChatReducer({...getReducerStateMock(), messages: [message, child1, child2]}, action)

  expect(state.messages.length).toBe(3)
  expect(selectActiveMessage).toHaveBeenCalled()
})

test('Unselect previous message', () => {
  const message = getMessageMock()
  const child1 = {
    ...getMessageMock(),
    id: '1',
    role: 'assistant',
    parentMessageID: message.id,
  } as CopilotChatMessage

  const child2 = {
    ...getMessageMock(),
    id: '2',
    role: 'assistant',
    parentMessageID: message.id,
  } as CopilotChatMessage

  const action: CopilotChatAction = {
    type: 'MESSAGES_UNSELECT_PREVIOUS_MESSAGE',
    message: child2,
  }
  const state = copilotChatReducer({...getReducerStateMock(), messages: [message, child1, child2]}, action)

  expect(state.messages.length).toBe(3)
  expect(unselectPreviousChild).toHaveBeenCalled()
})

describe('Set custom copilot', () => {
  it('updates existing custom copilot when ID and owner matches if owner is present', () => {
    const existingCopilot: CustomCopilot = getCustomCopilotMock({
      id: 1,
      oldId: 1,
      owner: 'owner1',
      name: 'Old Name',
      slug: 'old-name',
      slugWithOwner: 'owner1/old-name',
    })

    const updatedCopilot: CustomCopilot = getCustomCopilotMock({
      id: 1,
      oldId: 1,
      owner: 'owner1',
      name: 'New Name',
      slug: 'new-name',
      slugWithOwner: 'owner1/update-name',
    })

    const action = {type: 'SET_CUSTOM_COPILOT' as const, customCopilot: updatedCopilot}
    const state = copilotChatReducer(
      {
        ...getReducerStateMock(),
        customCopilots: [existingCopilot],
      },
      action,
    )
    expect(state.customCopilots).toEqual([updatedCopilot])
  })

  it('updates existing custom copilot matching only on oldId when updated copilot has no owner', () => {
    const existingCopilot: CustomCopilot = getCustomCopilotMock({
      id: 1,
      oldId: 1,
      name: 'Old Name',
      slug: 'old-name',
      slugWithOwner: 'owner1/old-name',
    })

    const otherCopilot: CustomCopilot = getCustomCopilotMock({
      id: 2,
      oldId: 2,
      owner: 'owner1',
      name: 'Other Name',
      slug: 'other-name',
      slugWithOwner: 'owner1/other-name',
    })

    const updatedCopilot: CustomCopilot = getCustomCopilotMock({
      id: 1,
      oldId: 1,
      name: 'New Name',
      slug: 'new-name',
      slugWithOwner: 'new-name',
    })

    const action = {type: 'SET_CUSTOM_COPILOT' as const, customCopilot: updatedCopilot}
    const state = copilotChatReducer(
      {
        ...getReducerStateMock(),
        customCopilots: [existingCopilot, otherCopilot],
      },
      action,
    )
    expect(state.customCopilots).toEqual([updatedCopilot, otherCopilot])
  })

  it('creates new array with custom copilot when customCopilots is undefined', () => {
    const newCopilot: CustomCopilot = getCustomCopilotMock({
      id: 1,
      oldId: 1,
      name: 'New Copilot',
      slug: 'new-copilot',
      slugWithOwner: 'new-copilot',
    })

    const action = {type: 'SET_CUSTOM_COPILOT' as const, customCopilot: newCopilot}
    const state = copilotChatReducer(
      {
        ...getReducerStateMock(),
        customCopilots: undefined,
      },
      action,
    )
    expect(state.customCopilots).toEqual([newCopilot])
  })

  it('preserves other custom copilots when updating one', () => {
    const existingCopilot1: CustomCopilot = getCustomCopilotMock({
      id: 1,
      oldId: 1,
      name: 'First Copilot',
      slug: 'first-copilot',
      slugWithOwner: 'first-copilot',
    })

    const existingCopilot2: CustomCopilot = getCustomCopilotMock({
      id: 2,
      oldId: 2,
      name: 'Second Copilot',
      slug: 'second-copilot',
      slugWithOwner: 'second-copilot',
    })

    const updatedCopilot: CustomCopilot = getCustomCopilotMock({
      id: 1,
      oldId: 1,
      name: 'Updated First',
      slug: 'updated-first',
      slugWithOwner: 'updated-first',
    })

    const action = {type: 'SET_CUSTOM_COPILOT' as const, customCopilot: updatedCopilot}
    const state = copilotChatReducer(
      {
        ...getReducerStateMock(),
        customCopilots: [existingCopilot1, existingCopilot2],
      },
      action,
    )
    expect(state.customCopilots).toEqual([updatedCopilot, existingCopilot2])
  })
})
