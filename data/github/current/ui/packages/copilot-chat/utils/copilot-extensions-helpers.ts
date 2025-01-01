import type {CopilotChatAgent, CustomCopilot} from './copilot-chat-types'
import {isCustomCopilot} from './custom-copilots-helpers'

export function getSlugFromExtension(extension: CopilotChatAgent | CustomCopilot): string {
  return isCustomCopilot(extension) ? extension.slugWithOwner : extension.slug
}
