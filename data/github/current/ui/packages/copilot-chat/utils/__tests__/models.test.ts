import {type CopilotChatModel, type CopilotModel, CopilotPlan} from '../copilot-chat-types'
import {copilotFeatureFlags} from '../copilot-feature-flags'
import {findDefaultModel, hasLimitedCapabilities, toCopilotChatModels} from '../models'

const baseModel: CopilotChatModel = {
  id: 'base',
  name: 'Base Model',
  version: '1',
  // eslint-disable-next-line camelcase
  model_picker_enabled: true,
  vendor: 'A Vendor',
  preview: false,
  capabilities: {
    family: 'gpt-4o',
    limits: {
      // eslint-disable-next-line camelcase
      max_prompt_tokens: 10000,
    },
    supports: {
      // eslint-disable-next-line camelcase
      tool_calls: undefined,
      // eslint-disable-next-line camelcase
      parallel_tool_calls: undefined,
    },
    tokenizer: 'o200k_base',
    type: 'chat',
  },
  displayName: 'Base Model',
  hasLimitedCapabilities: false,
  isThirdParty: false,
}

describe('toCopilotChatModels', () => {
  it('filters out non-chat models', () => {
    const nonChatModel = {
      ...baseModel,
      capabilities: {
        ...baseModel.capabilities,
        type: 'code',
      },
    }
    const models = toCopilotChatModels([nonChatModel])
    expect(models).toHaveLength(0)
  })

  it('filters out models that we do not have terms for', () => {
    const unconfiguredModelWithoutTerms: CopilotModel = {
      ...baseModel,
      id: 'unconfigured',
      policy: {
        state: 'unconfigured',
        terms: undefined,
      },
    }
    const acceptedModelWithoutTerms: CopilotModel = {
      ...baseModel,
      id: 'enabled',
      policy: {
        state: 'enabled',
        terms: undefined,
      },
    }
    const models = toCopilotChatModels([unconfiguredModelWithoutTerms, acceptedModelWithoutTerms])
    expect(models).toHaveLength(1)
    expect(models[0]?.id).toBe('enabled')
  })

  it('filters out models that are not enabled for the model picker', () => {
    const nonAllowedModel = {
      ...baseModel,
      // eslint-disable-next-line camelcase
      model_picker_enabled: false,
    }
    const models = toCopilotChatModels([nonAllowedModel])
    expect(models).toHaveLength(0)
  })

  it('filters out models that are not enabled', () => {
    const disabledModel = {
      ...baseModel,
      // eslint-disable-next-line camelcase
      model_picker_enabled: false,
    }
    const models = toCopilotChatModels([disabledModel])
    expect(models).toHaveLength(0)
  })

  it('strips any preview labels out of the display name', () => {
    const model: CopilotModel = {
      ...baseModel,
      name: 'GPT-4o (Preview)',
    }
    const betaModel: CopilotModel = {
      ...baseModel,
      name: 'GPT-4o (Beta)',
    }
    const models = toCopilotChatModels([model, betaModel, baseModel])

    expect(models).toHaveLength(3)
    expect(models[0]?.displayName).toBe('GPT-4o')
    expect(models[1]?.displayName).toBe('GPT-4o')
    expect(models[2]?.displayName).toBe('Base Model')
  })
})

describe('hasLimitedCapabilities', () => {
  it('o1-ga is limited unless parameter is specified', () => {
    const o1GAModel: CopilotModel = {
      id: 'o1-ga-model',
      name: 'O1 GA Model',
      version: '1',
      // eslint-disable-next-line camelcase
      model_picker_enabled: true,
      vendor: 'Azure OpenAI',
      preview: false,
      capabilities: {
        family: 'o1-ga',
        // eslint-disable-next-line camelcase
        limits: {max_prompt_tokens: 10000},
        supports: {
          // eslint-disable-next-line camelcase
          tool_calls: true,
          // eslint-disable-next-line camelcase
          parallel_tool_calls: true,
        },
        tokenizer: 'o200k_base',
        type: 'chat',
      },
    }

    // When tool flag is enabled, hasLimitedCapabilities should be false.
    expect(hasLimitedCapabilities(o1GAModel, true)).toBe(false)
    // When tool flag is disabled, hasLimitedCapabilities should be true.
    expect(hasLimitedCapabilities(o1GAModel, false)).toBe(true)
  })

  it('other models are limited unless they support tool calls', () => {
    const nonO1Model: CopilotModel = {
      id: 'non-o1-model',
      name: 'Non O1 Model',
      version: '1',
      // eslint-disable-next-line camelcase
      model_picker_enabled: true,
      vendor: 'Another Vendor',
      preview: false,
      capabilities: {
        family: 'gpt-4o',
        // eslint-disable-next-line camelcase
        limits: {max_prompt_tokens: 10000},
        supports: {
          // eslint-disable-next-line camelcase
          tool_calls: true,
          // eslint-disable-next-line camelcase
          parallel_tool_calls: true,
        },
        tokenizer: 'o200k_base',
        type: 'chat',
      },
    }

    // When tool_calls is true, hasLimitedCapabilities should be false regardless of the flag.
    expect(hasLimitedCapabilities(nonO1Model, true)).toBe(false)
    expect(hasLimitedCapabilities(nonO1Model, false)).toBe(false)

    const nonO1LimitedModel: CopilotModel = {
      ...nonO1Model,
      capabilities: {
        ...nonO1Model.capabilities,
        supports: {
          // eslint-disable-next-line camelcase
          tool_calls: false,
          // eslint-disable-next-line camelcase
          parallel_tool_calls: true,
        },
      },
    }
    // When tool_calls is false, hasLimitedCapabilities should be true.
    expect(hasLimitedCapabilities(nonO1LimitedModel, true)).toBe(true)
    expect(hasLimitedCapabilities(nonO1LimitedModel, false)).toBe(true)
  })

  it('returns the chat fallback model when quota is exceeded', () => {
    jest.spyOn(copilotFeatureFlags, 'premiumRequestQuotasEnabled', 'get').mockReturnValue(true)
    const defaultModel: CopilotChatModel = {
      ...baseModel,
      id: 'default-model',
      name: 'Default Model',
      // eslint-disable-next-line camelcase
      is_chat_default: true,
      // eslint-disable-next-line camelcase
      is_chat_fallback: false,
    }
    const fallbackModel: CopilotChatModel = {
      ...baseModel,
      id: 'fallback-model',
      name: 'Fallback Model',
      // eslint-disable-next-line camelcase
      is_chat_default: false,
      // eslint-disable-next-line camelcase
      is_chat_fallback: true,
    }
    const models = [defaultModel, fallbackModel]
    const model = findDefaultModel(models, CopilotPlan.IndividualPro, true, false)
    expect(model).toEqual(fallbackModel)
  })

  it('returns the chat default model when quota is not exceeded', () => {
    jest.spyOn(copilotFeatureFlags, 'premiumRequestQuotasEnabled', 'get').mockReturnValue(true)
    const defaultModel: CopilotChatModel = {
      ...baseModel,
      id: 'default-model',
      name: 'Default Model',
      // eslint-disable-next-line camelcase
      is_chat_default: true,
      // eslint-disable-next-line camelcase
      is_chat_fallback: false,
    }
    const fallbackModel: CopilotChatModel = {
      ...baseModel,
      id: 'fallback-model',
      name: 'Fallback Model',
      // eslint-disable-next-line camelcase
      is_chat_default: false,
      // eslint-disable-next-line camelcase
      is_chat_fallback: true,
    }
    const models = [defaultModel, fallbackModel]
    const model = findDefaultModel(models, CopilotPlan.IndividualPro, false, false)
    expect(model).toEqual(defaultModel)
  })
})
