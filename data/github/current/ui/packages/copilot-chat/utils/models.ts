import type {CopilotChatModel, CopilotModel} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'

const OPEN_AI_LOGO = '/images/modules/marketplace/models/families/openai.svg'
const ANTHROPIC_LOGO = '/images/modules/marketplace/models/families/anthropic.svg'
const GEMINI_LOGO = '/images/modules/marketplace/models/families/gemini.svg'

const LOGO_BY_VENDOR = new Map([
  ['Azure OpenAI', OPEN_AI_LOGO],
  ['Anthropic', ANTHROPIC_LOGO],
  ['Google', GEMINI_LOGO],
])

export function generateDefaultModel(): CopilotChatModel {
  return {
    capabilities: {
      family: 'gpt-4o',
      limits: {
        // eslint-disable-next-line camelcase
        max_prompt_tokens: 20000,
        vision: {
          // eslint-disable-next-line camelcase
          supported_media_types: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
        },
      },
      supports: {
        // eslint-disable-next-line camelcase
        parallel_tool_calls: true,
        // eslint-disable-next-line camelcase
        tool_calls: true,
      },
      tokenizer: 'o200k_base',
      type: 'chat',
    },
    id: 'gpt-4o',
    name: 'GPT 4o',
    version: 'gpt-4o-2024-05-13',
    displayName: 'GPT 4o',
    vendor: 'Azure OpenAI',
    logoURL: OPEN_AI_LOGO,
    hasLimitedCapabilities: false,
    preview: false,
    isThirdParty: false,
    // eslint-disable-next-line camelcase
    model_picker_enabled: true,
  }
}

export const DEFAULT_MODEL = generateDefaultModel()

export function toCopilotChatModels(copilotModels: CopilotModel[]) {
  const baseModels = copilotModels ?? [DEFAULT_MODEL]
  const allowedModels = baseModels.map(toAllowedCopilotChatModel).filter(m => !!m)
  return allowedModels.filter(m => m.model_picker_enabled)
}

function toAllowedCopilotChatModel(copilotModel: CopilotModel): CopilotChatModel | null {
  if (!isChatModel(copilotModel)) return null
  if (!isAllowed(copilotModel)) return null
  return {
    ...copilotModel,
    displayName: displayName(copilotModel),
    hasLimitedCapabilities: hasLimitedCapabilities(copilotModel, copilotFeatureFlags.copilotChatO1Tools),
    isThirdParty: isThirdParty(copilotModel),
    logoURL: LOGO_BY_VENDOR.get(copilotModel.vendor),
  }
}

export function hasLimitedCapabilities(m: CopilotModel, o1ToolsEnabled: boolean) {
  if (m.capabilities.family === 'o1-ga') {
    return !o1ToolsEnabled
  }
  return !m.capabilities.supports.tool_calls
}

function isAllowed(m: CopilotModel) {
  if (!m.model_picker_enabled) return false

  if (m.policy && m.policy.state !== 'enabled' && !m.policy.terms) {
    // If the model has a policy that must be accepted but we have no terms to show the user,
    // there is no valid way for them to use the model and we should not show it.
    return false
  }

  return true
}

function isThirdParty(m: CopilotModel) {
  return m.vendor !== 'Azure OpenAI'
}

function isChatModel(m: CopilotModel): m is CopilotChatModel {
  return m.capabilities.type === 'chat'
}

const betaLabels = ['(Beta)', '(Preview)']
function displayName(m: CopilotModel) {
  for (const suffix of betaLabels) {
    if (m.name.endsWith(suffix)) {
      return m.name.replace(suffix, '').trim()
    }
  }
  return m.name
}
