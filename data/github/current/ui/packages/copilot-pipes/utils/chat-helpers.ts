import {sanitizePipeline} from './pipes'
import type {Pipeline} from '../types/app'
import type {CopilotChatMessage} from '@github-ui/copilot-chat/utils/copilot-chat-types'

/**
 * Get the latest pipe from chat by looking through message references and trying to parse out a pipe JSON from
 * any text references.
 *
 * TODO: update pipes to use specific reference type https://github.com/github/copilot-productivity/issues/4081
 */
export function getLatestPipe(
  selectedThreadId: string | null,
  messages: CopilotChatMessage[],
): {messageId: string; pipeline: Pipeline} | undefined {
  for (const message of [...messages].reverse()) {
    for (const ref of message.references ?? []) {
      if (ref.type !== 'text' || !ref.text) continue
      try {
        const pipe = JSON.parse(ref.text)
        if (isPipe(pipe)) {
          const sanitizedPipe = sanitizePipeline(pipe, [])

          // temporary workaround to pipes not being generated with ids
          sanitizedPipe.id = selectedThreadId ?? pipe.title.replace(/\s+/g, '-').toLowerCase()
          return {messageId: message.id, pipeline: sanitizedPipe}
        }
      } catch {
        continue
      }
    }
  }
  return undefined
}

function isPipe(obj: unknown): obj is Pipeline {
  return !!obj && typeof obj === 'object' && 'title' in obj && 'nodes' in obj
}
