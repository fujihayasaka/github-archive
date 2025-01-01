// eslint-disable-next-line import/no-namespace
import * as stableHelpers from './copilot-chat-subthreading-helpers-stable'
// eslint-disable-next-line import/no-namespace
import * as unstableHelpers from './copilot-chat-subthreading-helpers-unstable'
import type {CopilotChatMessage} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'

export function addMessageToHierarchy(
  messages: ReadonlyArray<Readonly<CopilotChatMessage>>,
  newMessage: CopilotChatMessage,
): ReadonlyArray<Readonly<CopilotChatMessage>> {
  return copilotFeatureFlags.stableSubthreadingHelpers
    ? stableHelpers.addMessageToHierarchy(messages, newMessage)
    : unstableHelpers.addMessageToHierarchy(messages, newMessage)
}

export function constructMessagesHierarchy(
  messages: ReadonlyArray<Readonly<CopilotChatMessage>>,
  selectMostRecentMessages: boolean = true,
): ReadonlyArray<Readonly<CopilotChatMessage>> {
  return copilotFeatureFlags.stableSubthreadingHelpers
    ? stableHelpers.constructMessagesHierarchy(messages, selectMostRecentMessages)
    : unstableHelpers.constructMessagesHierarchy(messages, selectMostRecentMessages)
}

export function getActiveMessages(messages: readonly CopilotChatMessage[]): CopilotChatMessage[] {
  return copilotFeatureFlags.stableSubthreadingHelpers
    ? stableHelpers.getActiveMessages(messages)
    : unstableHelpers.getActiveMessages(messages)
}

export function getParentMessage(
  messages: readonly CopilotChatMessage[],
  message: CopilotChatMessage,
): CopilotChatMessage | undefined {
  return copilotFeatureFlags.stableSubthreadingHelpers
    ? stableHelpers.getParentMessage(messages, message)
    : unstableHelpers.getParentMessage(messages, message)
}

export function selectActiveMessage(
  messages: readonly CopilotChatMessage[],
  selectedMessage: CopilotChatMessage,
): CopilotChatMessage[] {
  return copilotFeatureFlags.stableSubthreadingHelpers
    ? stableHelpers.selectActiveMessage(messages, selectedMessage)
    : unstableHelpers.selectActiveMessage(messages, selectedMessage)
}

export function unselectPreviousChild(
  messages: readonly CopilotChatMessage[],
  parentMessage: CopilotChatMessage,
): CopilotChatMessage[] {
  return copilotFeatureFlags.stableSubthreadingHelpers
    ? stableHelpers.unselectPreviousChild(messages, parentMessage)
    : unstableHelpers.unselectPreviousChild(messages, parentMessage)
}

export const updateCompletedMessageParent = stableHelpers.updateCompletedMessageParent
