import {sendEvent} from '@github-ui/hydro-analytics'

import type {CopilotChatMessage} from './copilot-chat-types'

/**
 * Constructs the message hierarchy, populating parentMessageIndex & childMessageIndexes using parentMessageID reference in each message.
 * @param messages complete array of messages
 * @param selectMostRecentMessages whether to update the selected messages to the most recent child message
 * @returns a new list of messages with subthreading (parent/child) attributes populated
 */
export function constructMessagesHierarchy(
  messages: ReadonlyArray<Readonly<CopilotChatMessage>>,
  selectMostRecentMessages: boolean = true,
): ReadonlyArray<Readonly<CopilotChatMessage>> {
  const startTime = performance.now()
  let timeElapsed = 0

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
  if (messages.length === 0) {
    messages = [rootMessage]

    timeElapsed = performance.now() - startTime
    sendEvent('copilot.timings', {
      function: 'constructMessagesHierarchy',
      timeElapsed,
      messagesLength: messages.length,
      selectMostRecentMessages,
    })
    return messages
  }

  // Handle messages coming from the old structure that did not have a root node yet.
  if (messages[0]!.id !== 'root') {
    messages = [rootMessage, ...messages]

    sendEvent('copilot.legacy_thread_updated', {
      threadID: messages[1]!.threadID,
      messagesLength: messages.length,
      selectMostRecentMessages,
    })
  }

  // Virtual "termination" parent message ID that gets sent to server if first message is edited, to disambiguate
  // all potential first messages. Point the first message to the root message.
  // See service.go
  let previousMessage = messages[1]
  if (!previousMessage) {
    return messages
  }

  ;[messages, previousMessage] = mutate(messages, 1, 'parentMessageID', 'root')

  const messageIdToIndex = new Map<string, number>()

  const allChildMessageIndexes: number[][] = []
  // eslint-disable-next-line prefer-const
  for (let [index, message] of messages.entries()) {
    ;[messages, message] = mutate(messages, index, 'messageIndex', index)
    allChildMessageIndexes[index] = []
    messageIdToIndex.set(message.id, index)

    if (message.id === 'root') {
      continue
    }

    // Handle messages with no parent, which come from the old flat structure.
    // We iterate from oldest to most recent, linking each message to the previous one as its parent.
    if (!message.parentMessageID) {
      ;[messages, message] = mutate(messages, index, 'parentMessageID', previousMessage.id)

      previousMessage = message
    }

    // By the time we get here, each message should have a parent. We can now link the parents to their children
    // by adding them to the list of childMessages on the parent.
    const parentMessageIndex = messageIdToIndex.get(message.parentMessageID!)
    if (parentMessageIndex !== undefined) {
      ;[messages, message] = mutate(messages, index, 'parentMessageIndex', parentMessageIndex)
      let parentMessage = messages[parentMessageIndex]
      if (parentMessage) {
        allChildMessageIndexes[parentMessageIndex]!.push(index)

        // In the event of reconstruction, we want to preserve the selected child index.
        if (parentMessage.selectedChildIndex === undefined) {
          ;[messages, parentMessage] = mutate(messages, parentMessageIndex, 'selectedChildIndex', index)
        }
      }
    }
  }

  for (let i = 0; i < messages.length; i++) {
    ;[messages] = mutate(messages, i, 'childMessageIndexes', allChildMessageIndexes[i])
  }

  // We want the selected subthreads to show the most recent message by default.
  // Start with the most recent message and work backward to determine which
  // messages to select.
  if (selectMostRecentMessages) {
    let selectedNode = messages.at(-1)
    while (selectedNode) {
      let parent = getParentMessage(messages, selectedNode)
      const parentIndex = messageIdToIndex.get(parent?.id ?? '')
      if (parentIndex !== undefined) {
        ;[messages, parent] = mutate(messages, parentIndex, 'selectedChildIndex', selectedNode.messageIndex)
      }

      selectedNode = parent
    }
  }

  timeElapsed = performance.now() - startTime
  sendEvent('copilot.timings', {
    function: 'constructMessagesHierarchy',
    timeElapsed,
    messagesLength: messages.length,
    selectMostRecentMessages,
  })

  return messages
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
  messages: ReadonlyArray<Readonly<CopilotChatMessage>>,
  newMessage: CopilotChatMessage,
): ReadonlyArray<Readonly<CopilotChatMessage>> {
  const parentMessageIndex = messages.findIndex(m => m.id === newMessage?.parentMessageID)

  if (parentMessageIndex !== -1) {
    let parentMessage = messages[parentMessageIndex]!

    const messageToAdd = {...newMessage}
    messageToAdd.messageIndex = messages.length
    messageToAdd.childMessageIndexes = []
    messageToAdd.parentMessageIndex = parentMessage.messageIndex

    const parentChildMessageIndexes = parentMessage.childMessageIndexes?.slice() || []
    if (!parentChildMessageIndexes.includes(messageToAdd.messageIndex)) {
      parentChildMessageIndexes.push(messageToAdd.messageIndex)
    }
    parentMessage = {
      ...parentMessage,
      childMessageIndexes: parentChildMessageIndexes,
      selectedChildIndex: messageToAdd.messageIndex,
    }
    messages = [...messages, messageToAdd].toSpliced(parentMessageIndex, 1, parentMessage)
  }

  return messages
}

export function updateCompletedMessageParent(
  messages: ReadonlyArray<Readonly<CopilotChatMessage>>,
  newMessage: CopilotChatMessage,
): ReadonlyArray<Readonly<CopilotChatMessage>> {
  // Find last user message that user sent and set its ID to the parent message ID we got from response.
  // We need this because server is not returning the user message information back, just the response message.
  // But the response message should be having the correct parent message id that we can use here.

  // TODO: this likely should be updated to handle subthreads being changed by user while response is being streamed back
  // so that we would find the correct user message. Probably easiest is to find a user message with a missing ID - we should only have one.
  // Is it possible to switch subthreads while response is being streamed? We do seem to cancel and nullify state.streamingMessage
  // on failures and stops (see below) - we should do same with subthreads.

  // Note that before this change, user messages are storing fake client-side generated IDs (built by buildMessage method) until thread is reloaded.

  const parentMessage = messages.find(m => m.id === newMessage?.parentMessageID)
  if (parentMessage == null) {
    const activeMessages = getActiveMessages(messages)
    let lastActiveMessage = activeMessages[activeMessages.length - 1]
    if (lastActiveMessage !== undefined) {
      if (lastActiveMessage.clientSide && lastActiveMessage.role === 'user') {
        const lastActiveMessageIndex = messages.indexOf(lastActiveMessage)
        // If it's user message they submitted, change its ID to the one generated by server
        ;[messages, lastActiveMessage] = mutate(messages, lastActiveMessageIndex, 'id', newMessage.parentMessageID!)
        // Mark message as available on server, so it can be used to chain future messages to
        // This code will need to stay even if above line is no longer neccesary due to relying on client-side IDs
        // ref https://github.com/github/copilot-productivity/issues/3613
        ;[messages, lastActiveMessage] = mutate(messages, lastActiveMessageIndex, 'clientSide', false)
      } else {
        // If previous message is client-only non-user (assistant) message, chain to that
        newMessage.parentMessageID = lastActiveMessage.id
      }
    }
  }
  return messages
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

/**
 * Given: an array of messages, the index of the message to edit, the key to change, and the new value this function:
 * 1. If the key already has the given value, does nothing.
 * 2. Otherwise, it clones the message, sets the value, clones the message array, and puts the new message object in the new message array and returns that.
 *
 * This supports changing the minimum number of ChatMessage objects possible, which is important to prevent unnecessary re-renders.
 */
function mutate<K extends keyof CopilotChatMessage>(
  messages: ReadonlyArray<Readonly<CopilotChatMessage>>,
  index: number,
  key: K,
  value: CopilotChatMessage[K],
): [ReadonlyArray<Readonly<CopilotChatMessage>>, CopilotChatMessage] {
  const message = messages[index]
  if (!message) throw new Error(`Message at index ${index} does not exist.`)
  const currentValue = message[key]
  if (currentValue === value) {
    return [messages, message]
  }
  if (
    Array.isArray(currentValue) &&
    Array.isArray(value) &&
    currentValue.length === value.length &&
    currentValue.every((v, i) => v === value[i])
  ) {
    return [messages, message]
  }

  const newMessage = {
    ...message,
    [key]: value,
  } as CopilotChatMessage
  const newMessages = [...messages]
  newMessages[index] = newMessage
  return [newMessages, newMessages[index]]
}
