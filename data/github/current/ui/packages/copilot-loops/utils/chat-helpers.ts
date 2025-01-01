import {sanitizePipeline} from './pipes'
import type {Pipeline} from '../types/app'
import type {CopilotChatMessage} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {REFERENCE_TYPE_LOOP} from './constants'

/**
 * Extract a loop/pipeline from a chat message if it contains a loop reference.
 */
export function getLoopFromChatMessage(
  message: CopilotChatMessage,
): {messageId: string; pipeline: Pipeline} | undefined {
  for (const ref of message.references ?? []) {
    if (ref.type === REFERENCE_TYPE_LOOP) {
      if (isPipe(ref)) {
        const pipe: Pipeline = {
          description: ref.description,
          id: ref.id,
          title: ref.title,
          nodes: ref.nodes,
          updatedAt: message.createdAt,
        }

        const sanitizedPipe = sanitizePipeline(pipe, [])
        return {messageId: message.id, pipeline: sanitizedPipe}
      }
    }
  }
  return undefined
}

/**
 * Get the latest pipe from chat by looking for a pipe reference in the thread.
 */
export function getLatestPipe(
  selectedThreadId: string | null,
  messages: readonly CopilotChatMessage[],
  searchUserMessages = false,
): {messageId: string; pipeline: Pipeline} | undefined {
  for (const message of [...messages].reverse()) {
    if (message.role !== 'assistant' && !searchUserMessages) continue

    const loopResult = getLoopFromChatMessage(message)
    if (loopResult) {
      return loopResult
    }
  }
  return undefined
}

function isPipe(obj: unknown): obj is Pipeline {
  return !!obj && typeof obj === 'object' && 'title' in obj && 'nodes' in obj
}
