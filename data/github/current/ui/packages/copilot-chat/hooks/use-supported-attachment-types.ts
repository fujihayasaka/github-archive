import type {SupportedReferenceType} from '../components/ReferencesSelectPanel'
import {isRepository} from '../utils/copilot-chat-helpers'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState, useChatStateValues} from '../utils/CopilotChatContext'
import {useSelectedCustomCopilotId} from './use-selected-custom-copilot-id'

export type SupportedAttachmentType = 'repositories' | 'references' | 'knowledge-bases' | 'upload' | 'agents'

/**
 * Returns the supported attachment types and reference types based on the current state of the chat.
 * Reference types are specifically used in the ReferencesSelectPanel component.
 */
export function useSupportedAttachmentTypes(): {
  supportedAttachmentTypes: SupportedAttachmentType[]
  supportedReferenceTypes: SupportedReferenceType[]
} {
  const state = useChatState()
  const {model} = useChatStateValues('model')
  const isCopilotSpaceAttachments = useSelectedCustomCopilotId() !== null

  const supportedAttachmentTypes: SupportedAttachmentType[] = []

  const referencesEnabled = copilotFeatureFlags.topicsAsReferences ? true : isRepository(state.currentTopic)

  const shouldShowKnowledge =
    state.renderKnowledgeBases && ((state.currentTopic && isRepository(state.currentTopic)) || !state.currentTopic)

  const imageUploadsEnabled =
    (copilotFeatureFlags.attachImagesImmersive && state.mode === 'immersive' && !!model.capabilities.supports.vision) ||
    false
  const textUploadsEnabled = copilotFeatureFlags.pasteTextFiles

  if (!isCopilotSpaceAttachments) {
    supportedAttachmentTypes.push('repositories')
  }

  if (referencesEnabled) {
    supportedAttachmentTypes.push('references')
  }

  if (shouldShowKnowledge && !isCopilotSpaceAttachments) {
    supportedAttachmentTypes.push('knowledge-bases')
  }

  if (imageUploadsEnabled || textUploadsEnabled) {
    supportedAttachmentTypes.push('upload')
  }

  if (!isCopilotSpaceAttachments) {
    supportedAttachmentTypes.push('agents')
  }
  const supportedReferenceTypes: SupportedReferenceType[] = isCopilotSpaceAttachments
    ? ['files']
    : ['files', 'folders', 'symbols']
  return {supportedAttachmentTypes, supportedReferenceTypes}
}
