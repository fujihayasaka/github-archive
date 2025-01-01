import type {CopilotModel} from '../copilot-chat-types'
import {toCopilotChatModels} from '../models'

const baseModel: CopilotModel = {
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
