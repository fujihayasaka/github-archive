import {sendEvent} from '@github-ui/hydro-analytics'

import type {CopilotChatMessage} from './copilot-chat-types'

/**
 * Constructs the message hierarchy, populating parentMessageIndex & childMessageIndexes using parentMessageID reference in each message.
 * @param messages complete array of messages
 * @param selectMostRecentMessages whether to update the selected messages to the most recent child message
 * @returns a new list of messages with subthreading (parent/child) attributes populated
 */
export function constructMessagesHierarchy(
  messages: readonly CopilotChatMessage[],
  selectMostRecentMessages: boolean = true,
): CopilotChatMessage[] {
  const startTime = performance.now()
  let timeElapsed = 0

  const messagesClone = messages.map(m => ({...m}))

  const rootMessage: CopilotChatMessage = {
    id: 'root',
    role: 'user',
    createdAt: '',
    threadID: '',
    references: null,
    childMessageIndexes: [],
    messageIndex: 0,
    clientSide: false,
  }

  // The first message does not have a parent. In order to keep track of possible edits to the first prompt,
  // we add an invisible root message that all first messages are linked to. This is pushed to the front of the array.
  if (messagesClone.length === 0) {
    messagesClone.push(rootMessage)

    timeElapsed = performance.now() - startTime
    sendEvent('copilot.timings', {
      function: 'constructMessagesHierarchy',
      timeElapsed,
      messagesLength: messagesClone.length,
      selectMostRecentMessages,
    })
    return messagesClone
  }

  // Handle messages coming from the old structure that did not have a root node yet.
  if (messagesClone[0]!.id !== 'root') {
    messagesClone.unshift(rootMessage)

    sendEvent('copilot.legacy_thread_updated', {
      threadID: messagesClone[1]!.threadID,
      messagesLength: messagesClone.length,
      selectMostRecentMessages,
    })
  }

  // Virtual "termination" parent message ID that gets sent to server if first message is edited, to disambiguate
  // all potential first messages. Point the first message to the root message.
  // See service.go
  let previousMessage: CopilotChatMessage | undefined = messagesClone[1]
  if (!previousMessage) {
    return messagesClone
  }

  previousMessage.parentMessageID = 'root'

  const messageIdToIndex = new Map<string, number>()

  for (const [index, message] of messagesClone.entries()) {
    message.messageIndex = index
    message.childMessageIndexes = []
    messageIdToIndex.set(message.id, index)

    if (message.id === 'root') {
      continue
    }

    // Handle messages with no parent, which come from the old flat structure.
    // We iterate from oldest to most recent, linking each message to the previous one as its parent.
    if (!message.parentMessageID) {
      message.parentMessageID = previousMessage.id
      previousMessage = message
    }

    // By the time we get here, each message should have a parent. We can now link the parents to their children
    // by adding them to the list of childMessages on the parent.
    const parentMessageIndex = messageIdToIndex.get(message.parentMessageID)
    if (parentMessageIndex !== undefined) {
      message.parentMessageIndex = parentMessageIndex
      const parentMessage = messagesClone[parentMessageIndex]
      if (parentMessage) {
        parentMessage.childMessageIndexes!.push(message.messageIndex)

        // In the event of reconstruction, we want to preserve the selected child index.
        if (parentMessage.selectedChildIndex === undefined) {
          parentMessage.selectedChildIndex = message.messageIndex
        }
      }
    }
  }

  // We want the selected subthreads to show the most recent message by default.
  // Start with the most recent message and work backward to determine which
  // messages to select.
  if (selectMostRecentMessages) {
    let selectedNode = messagesClone.at(-1)
    while (selectedNode) {
      const parent = getParentMessage(messagesClone, selectedNode)
      if (parent) {
        parent.selectedChildIndex = selectedNode.messageIndex
      }

      selectedNode = parent
    }
  }

  timeElapsed = performance.now() - startTime
  sendEvent('copilot.timings', {
    function: 'constructMessagesHierarchy',
    timeElapsed,
    messagesLength: messagesClone.length,
    selectMostRecentMessages,
  })

  return messagesClone
}

/**
 * @param messages complete array of messages
 * @returns the list of active messages (messages visible to the user)
 */
export function getActiveMessages(messages: readonly CopilotChatMessage[]): CopilotChatMessage[] {
  let currentNode = messages[0]
  const activeMessages: CopilotChatMessage[] = []
  while (currentNode) {
    if (currentNode.id !== 'root') {
      activeMessages.push(currentNode)
    }

    currentNode = currentNode.selectedChildIndex !== undefined ? messages[currentNode.selectedChildIndex] : undefined
  }

  return activeMessages
}

/**
 * @param messages complete array of messages
 * @param selectedMessage the message that should become active
 * @returns a new list of messages with the selectedMessage active
 */
export function selectActiveMessage(
  messages: readonly CopilotChatMessage[],
  selectedMessage: CopilotChatMessage,
): CopilotChatMessage[] {
  const messagesClone = messages.map(m => ({...m}))
  const parentMessage = messagesClone[selectedMessage.parentMessageIndex!]
  if (parentMessage) {
    parentMessage.selectedChildIndex = selectedMessage.messageIndex
  }
  return messagesClone
}

/**
 * @param messages complete array of messages
 * @param parentMessage the message from which to remove the selectedChildIndex
 * @returns a new list of messages with the provided parent childless
 */
export function unselectPreviousChild(
  messages: readonly CopilotChatMessage[],
  parentMessage: CopilotChatMessage,
): CopilotChatMessage[] {
  const messagesClone = messages.map(m => ({...m}))
  const messageToUpdate = messagesClone[parentMessage.messageIndex!]
  if (messageToUpdate && messageToUpdate.selectedChildIndex !== undefined) {
    messageToUpdate.selectedChildIndex = undefined
  }
  return messagesClone
}

/**
 * Adds a message to the messages array, populating the parent/child attributes to maintain the hierarchy
 * @param messages complete array of messages
 * @param newMessage the message to add
 * @returns a new list of messages with newMessage appended to the end, and all parent/child attributes updated
 */
export function addMessageToHierarchy(
  messages: readonly CopilotChatMessage[],
  newMessage: CopilotChatMessage,
): CopilotChatMessage[] {
  const messagesClone = messages.map(m => ({...m}))
  const messageToAdd = {...newMessage}
  const parentMessage = messagesClone.find(m => m.id === messageToAdd?.parentMessageID)

  if (parentMessage) {
    messagesClone.push(messageToAdd)

    messageToAdd.messageIndex = messages.length
    messageToAdd.childMessageIndexes = []
    messageToAdd.parentMessageIndex = parentMessage.messageIndex

    parentMessage.childMessageIndexes ||= []
    if (!parentMessage.childMessageIndexes.includes(messageToAdd.messageIndex)) {
      parentMessage.childMessageIndexes.push(messageToAdd.messageIndex)
    }
    parentMessage.selectedChildIndex = messageToAdd.messageIndex
  }

  return messagesClone
}

/**
 * @param messages complete array of messages
 * @param message the message to get the parent of
 * @returns the parent of the given message
 */
export function getParentMessage(
  messages: readonly CopilotChatMessage[],
  message: CopilotChatMessage,
): CopilotChatMessage | undefined {
  return message.parentMessageIndex !== undefined ? messages[message.parentMessageIndex] : undefined
}
