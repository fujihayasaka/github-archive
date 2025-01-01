import {
  constructMessagesHierarchy,
  getActiveMessages,
  selectActiveMessage,
  unselectPreviousChild,
} from '../copilot-chat-subthreading-helpers'
import type {CopilotChatMessage} from '../copilot-chat-types'

describe('constructMessagesHierarchy', () => {
  it('pushes root node and returns early if messages list is empty', () => {
    let messages: CopilotChatMessage[] = []
    messages = constructMessagesHierarchy(messages)
    expect(messages[0]?.id).toBe('root')
  })

  it('constructs parent-child relationships for legacy structure', () => {
    // Original structure with no subthreading, so all messages start with no parentMessageID
    // Expected outcome: root <-> 1 <-> 2 <-> 3 <-> 4
    let messages: CopilotChatMessage[] = [
      {
        id: '1',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
      },
      {
        id: '2',
        role: 'assistant',
        createdAt: '',
        threadID: '',
        references: null,
      },
      {
        id: '3',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
      },
    ]

    messages = constructMessagesHierarchy(messages)

    expect(messages.length).toBe(4) // 1 root message + 3 original messages

    expect(messages[0]?.id).toBe('root')
    expect(messages[1]?.parentMessageID).toBe('root')
    expect(messages[2]?.parentMessageID).toBe('1')
    expect(messages[3]?.parentMessageID).toBe('2')

    expect(messages[1]?.parentMessageIndex).toBe(0)
    expect(messages[2]?.parentMessageIndex).toBe(1)
    expect(messages[3]?.parentMessageIndex).toBe(2)

    expect(messages[0]?.selectedChildIndex).toBe(1)
    expect(messages[1]?.selectedChildIndex).toBe(2)
    expect(messages[2]?.selectedChildIndex).toBe(3)
    expect(messages[3]?.selectedChildIndex).toBe(undefined)

    expect(messages[0]?.childMessageIndexes).toEqual([1])
    expect(messages[1]?.childMessageIndexes).toEqual([2])
    expect(messages[2]?.childMessageIndexes).toEqual([3])
    expect(messages[3]?.childMessageIndexes).toEqual([])

    expect(messages[1]?.messageIndex).toEqual(1)
    expect(messages[2]?.messageIndex).toEqual(2)
    expect(messages[3]?.messageIndex).toEqual(3)
  })

  it('constructs parent-child relationships for new subthreading structure', () => {
    // All messages start with a parentMessageID pointing to the previous message
    // Expected outcome: root <-> 1 <- 2
    //                             \ <-> 3
    let messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
      },
      {
        id: '1',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: 'root',
      },
      // Create two responses from the same parent
      {
        id: '2',
        role: 'assistant',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '1',
      },
      {
        id: '3',
        role: 'assistant',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '1',
      },
    ]

    messages = constructMessagesHierarchy(messages)

    expect(messages.length).toBe(4)

    expect(messages[1]?.parentMessageIndex).toBe(0)
    expect(messages[2]?.parentMessageIndex).toBe(1)
    expect(messages[3]?.parentMessageIndex).toBe(1)

    expect(messages[0]?.selectedChildIndex).toBe(1)
    expect(messages[1]?.selectedChildIndex).toBe(3)
    expect(messages[2]?.selectedChildIndex).toBe(undefined)
    expect(messages[3]?.selectedChildIndex).toBe(undefined)

    expect(messages[0]?.childMessageIndexes).toEqual([1])
    expect(messages[1]?.childMessageIndexes).toEqual([2, 3])
    expect(messages[2]?.childMessageIndexes).toEqual([])
    expect(messages[3]?.childMessageIndexes).toEqual([])

    expect(messages[1]?.messageIndex).toEqual(1)
    expect(messages[2]?.messageIndex).toEqual(2)
    expect(messages[3]?.messageIndex).toEqual(3)
  })

  it('constructs parent-child relationships for a hybrid structure', () => {
    let messages: CopilotChatMessage[] = [
      // Original structure with no parentMessageID
      // Expected outcome: root <-> 1 <-> 2 <- 3 <-> 4
      //                                  \ <-> 5 <-> 6
      {
        id: '1',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
      },
      {
        id: '2',
        role: 'assistant',
        createdAt: '',
        threadID: '',
        references: null,
      },
      {
        id: '3',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        content: 'old message',
      },
      {
        id: '4',
        role: 'assistant',
        createdAt: '',
        threadID: '',
        references: null,
      },
      // New subthread that branches off of the legacy structure
      {
        id: '5',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        content: 'new message', // Edited user message based on id 3
        parentMessageID: '2',
      },
      {
        id: '6',
        role: 'assistant',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '5',
      },
    ]

    messages = constructMessagesHierarchy(messages)

    expect(messages.length).toBe(7) // 1 root message + 6 original messages

    expect(messages[0]?.id).toBe('root')
    expect(messages[1]?.parentMessageID).toBe('root')
    expect(messages[2]?.parentMessageID).toBe('1')
    expect(messages[3]?.parentMessageID).toBe('2')
    expect(messages[4]?.parentMessageID).toBe('3')

    expect(messages[1]?.parentMessageIndex).toBe(0)
    expect(messages[2]?.parentMessageIndex).toBe(1)
    expect(messages[3]?.parentMessageIndex).toBe(2)
    expect(messages[4]?.parentMessageIndex).toBe(3)
    expect(messages[5]?.parentMessageIndex).toBe(2)
    expect(messages[6]?.parentMessageIndex).toBe(5)

    expect(messages[0]?.selectedChildIndex).toBe(1)
    expect(messages[1]?.selectedChildIndex).toBe(2)
    expect(messages[2]?.selectedChildIndex).toBe(5)
    expect(messages[3]?.selectedChildIndex).toBe(4)
    expect(messages[4]?.selectedChildIndex).toBe(undefined)
    expect(messages[5]?.selectedChildIndex).toBe(6)
    expect(messages[6]?.selectedChildIndex).toBe(undefined)

    expect(messages[0]?.childMessageIndexes).toEqual([1])
    expect(messages[1]?.childMessageIndexes).toEqual([2])
    expect(messages[2]?.childMessageIndexes).toEqual([3, 5])
    expect(messages[3]?.childMessageIndexes).toEqual([4])
    expect(messages[4]?.childMessageIndexes).toEqual([])

    expect(messages[1]?.messageIndex).toEqual(1)
    expect(messages[2]?.messageIndex).toEqual(2)
    expect(messages[3]?.messageIndex).toEqual(3)
    expect(messages[4]?.messageIndex).toEqual(4)
    expect(messages[5]?.messageIndex).toEqual(5)
    expect(messages[6]?.messageIndex).toEqual(6)
  })

  it('properly handles edited first messages', () => {
    // Expected outcome: root <- 1 <-> 2
    //                     \ <-> 3
    let messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
      },
      {
        id: '1',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: 'root',
      },
      {
        id: '2',
        role: 'assistant',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '1',
      },
      // Edited first message
      {
        id: '3',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: 'root',
      },
    ]

    messages = constructMessagesHierarchy(messages)

    expect(messages.length).toBe(4)

    expect(messages[3]?.parentMessageIndex).toBe(0)
    expect(messages[0]?.childMessageIndexes).toEqual([1, 3])
    expect(messages[1]?.childMessageIndexes).toEqual([2])
    expect(messages[2]?.childMessageIndexes).toEqual([])

    expect(messages[0]?.selectedChildIndex).toBe(3)
    expect(messages[1]?.selectedChildIndex).toBe(2)
    expect(messages[2]?.selectedChildIndex).toBe(undefined)
    expect(messages[3]?.selectedChildIndex).toBe(undefined)

    expect(messages[1]?.messageIndex).toEqual(1)
    expect(messages[2]?.messageIndex).toEqual(2)
    expect(messages[3]?.messageIndex).toEqual(3)
  })

  it('selects the most recent messages by default', () => {
    // Starting structure: root <-> 1 <-> 2
    //                        \ <- 3
    // Expected outcome: root <- 1 <-> 2
    //                     \ <-> 3
    let messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
      },
      {
        id: '1',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: 'root',
      },
      {
        id: '2',
        role: 'assistant',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '1',
      },
      // Edited first message
      {
        id: '3',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: 'root',
      },
    ]

    // Build initial hierarchy
    messages = constructMessagesHierarchy(messages)
    // Update pointers to select an older subthread
    messages = unselectPreviousChild(messages, messages[0] as CopilotChatMessage)
    messages = selectActiveMessage(messages, messages[1] as CopilotChatMessage)

    expect(messages[0]?.selectedChildIndex).toBe(1)

    // Rebuild hierarchy
    messages = constructMessagesHierarchy(messages)

    expect(messages[0]?.selectedChildIndex).toBe(3)
  })

  it('does not select the most recent messages if selectMostRecentMessages is false', () => {
    // Starting structure: root - 1 - 2
    //                        \ - 3
    // Expected outcome: root <-> 1 <-> 2
    //                     \ <- 3
    let messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
      },
      {
        id: '1',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: 'root',
      },
      {
        id: '2',
        role: 'assistant',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '1',
      },
      // Edited first message
      {
        id: '3',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: 'root',
      },
    ]

    // Build initial hierarchy
    messages = constructMessagesHierarchy(messages, false)

    expect(messages[0]?.selectedChildIndex).toBe(1)
    expect(messages[1]?.selectedChildIndex).toBe(2)
  })
})

describe('getActiveMessages', () => {
  it('returns an empty array if there are no user or assistant messages', () => {
    const messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
      },
    ]
    const activeMessages = getActiveMessages(messages)
    expect(activeMessages).toEqual([])
  })

  it('returns active messages based on selected child pointers', () => {
    // Starting structure: root <- 1 <- 2 <- 3 <- 4
    //                                  \ <- 5
    // Expected result: 1 <- 2 <- 5
    let messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
      },
      {
        id: '1',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: 'root',
      },
      {
        id: '2',
        role: 'assistant',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '1',
      },
      {
        id: '3',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '2',
      },
      {
        id: '4',
        role: 'assistant',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '3',
      },
      {
        id: '5',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '2', // edited user message from id 3, pointing to assistant's response with id 2
      },
    ]
    // Construct parent-child relationships
    messages = constructMessagesHierarchy(messages)
    // Update selected message
    const messageToSelect = messages[5] as CopilotChatMessage
    messages = selectActiveMessage(messages, messageToSelect)

    const activeMessages = getActiveMessages(messages)
    expect(activeMessages).toEqual([messages[1], messages[2], messages[5]])
  })

  it('returns active messages based on selected child pointers for a single message', () => {
    // Starting structure: root <- 1
    //                        \ <- 2
    // Expected result: 2
    let messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
      },
      {
        id: '1',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: 'root',
      },
      {
        id: '2',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: 'root',
      },
    ]
    // Construct parent-child relationships
    messages = constructMessagesHierarchy(messages)
    // Update selected message
    const messageToSelect = messages[2] as CopilotChatMessage
    messages = selectActiveMessage(messages, messageToSelect)

    const activeMessages = getActiveMessages(messages)
    expect(activeMessages).toEqual([messages[2]])
  })
})

describe('selectActiveMessage', () => {
  it('does nothing if message does not have a parent', () => {
    const messageToSelect = {
      id: '1',
      role: 'user',
    } as CopilotChatMessage
    const messages = selectActiveMessage([], messageToSelect)

    expect(messages.length === 0).toBeTruthy()
    expect(messageToSelect.parentMessageIndex).toBe(undefined)
  })

  it('updates the selected child index of the parent message', () => {
    // Starting structure: root -> 1  2 -> 4
    //                              \-> 3 -> 5
    // Expected outcome: root -> 1 -> 2 -> 4
    //                              3 -> 5
    let messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
      },
      {
        id: '1',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: 'root',
      },
      {
        id: '2',
        role: 'assistant',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '1',
      },
      {
        id: '3',
        role: 'assistant',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '1',
      },
      {
        id: '4',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '2',
      },
      {
        id: '5',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '3',
      },
    ]

    messages = constructMessagesHierarchy(messages)
    expect(messages[1]?.selectedChildIndex).toBe(3)

    messages = selectActiveMessage(messages, messages[2] as CopilotChatMessage)
    expect(messages[1]?.selectedChildIndex).toBe(2)
    // Its own child pointer and the ones of its siblings should not be affected
    expect(messages[2]?.selectedChildIndex).toBe(4)
    expect(messages[3]?.selectedChildIndex).toBe(5)
  })
})

describe('unselectPreviousChild', () => {
  it('does nothing if message does not have a selected child', () => {
    const messageToSelect = {
      id: '1',
      role: 'user',
    } as CopilotChatMessage
    const messages = unselectPreviousChild([], messageToSelect)

    expect(messages.length === 0).toBeTruthy()
    expect(messageToSelect.selectedChildIndex).toBe(undefined)
  })

  it('sets the selected child index of the parent message to undefined', () => {
    // Starting structure: root -> 1 -> 2 -> 3
    // Expected result: root -> 1  2  3
    let messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
      },
      {
        id: '1',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: 'root',
      },
      {
        id: '2',
        role: 'assistant',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '1',
      },
      {
        id: '3',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        parentMessageID: '2',
      },
    ]

    messages = constructMessagesHierarchy(messages)
    expect(messages[1]?.selectedChildIndex).toBe(2)

    messages = unselectPreviousChild(messages, messages[1] as CopilotChatMessage)
    expect(messages[1]?.selectedChildIndex).toBe(undefined)
  })
})
