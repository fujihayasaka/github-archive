import type {CopilotChatThread} from '@github-ui/copilot-chat/utils/copilot-chat-types'

import {clearThreadTimePatch, getThreadTimePatch} from './local-storage'

/**
 * When we create a new thread, we might reuse an older, empty thread. In that case, we need to update the thread's
 * updatedAt time to the current time so that it appears at the top of the thread list. We store this hack in local
 * storage so that it persists across page navigations.
 */
export function patchThreadTime(threads: Map<string, CopilotChatThread>) {
  const patch = getThreadTimePatch()
  if (patch) {
    const thread = threads.get(patch.threadID)
    if (thread) {
      if (Date.parse(thread.updatedAt) <= patch.updatedAt) {
        thread.updatedAt = new Date(patch.updatedAt).toJSON()
      } else {
        clearThreadTimePatch()
      }
    }
  }
}
