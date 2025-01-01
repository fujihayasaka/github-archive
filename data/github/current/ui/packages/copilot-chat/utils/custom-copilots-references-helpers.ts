import type {CopilotChatReference} from './copilot-chat-types'

const isCustomCopilotRef = (ref: CopilotChatReference) => 'refOrigin' in ref && ref.refOrigin === 'custom_copilot'

export function filterOutCustomCopilotReferences(
  references: CopilotChatReference[] | null,
): CopilotChatReference[] | null {
  if (!Array.isArray(references)) return references

  return references.filter(ref => !isCustomCopilotRef(ref))
}
