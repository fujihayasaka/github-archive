import {
  mockGettingStarted,
  mockModel,
  mockModelInputSchema,
  mockModelInputSchemaParameters,
  mockModelIntegerInputSchemaParameter,
  mockModelDetails,
  mockModelState,
  mockNewMessages,
  mockNewParameters,
  mockNewSystemPrompt,
  mockChatInput,
  mockPreset,
  mockTokenUsage,
} from '../../routes/playground/__tests__/mocks'
import type {PlaygroundMessage, PlaygroundRequestParameters} from '../../types'
import {
  getModelState,
  combineParamsWithModel,
  getParameterSchema,
  hasDefaultParams,
  hasReachedMaxOutputTokens,
  validateAndFilterParameters,
  getMostRecentUserMessage,
} from '../model-state'

describe('validateAndFilterParameters', () => {
  it('updates the input values to the correct type', () => {
    const currentParams = {
      max_tokens: '500',
      temperature: '0.8',
      top_p: '0.1',
      stop: 'text',
    }

    const expectParams = {
      max_tokens: 500,
      temperature: 0.8,
      top_p: 0.1,
      stop: 'text',
    }
    expect(validateAndFilterParameters(mockModelInputSchemaParameters, currentParams)).toEqual(expectParams)
  })

  it('updates the input values to the acceptable min value', () => {
    const currentParams = {
      max_tokens: '99',
      temperature: '-1',
      top_p: '0.00',
      stop: 'text',
    }

    const expectParams = {
      max_tokens: 100,
      temperature: 0,
      top_p: 0.01,
      stop: 'text',
    }
    expect(validateAndFilterParameters(mockModelInputSchemaParameters, currentParams)).toEqual(expectParams)
  })

  it('updates the input values to the acceptable max value', () => {
    const currentParams = {
      max_tokens: '5000',
      temperature: '2',
      top_p: '2',
      stop: 'text',
    }

    const expectParams = {
      max_tokens: 4096,
      temperature: 1,
      top_p: 1,
      stop: 'text',
    }
    expect(validateAndFilterParameters(mockModelInputSchemaParameters, currentParams)).toEqual(expectParams)
  })

  it('removes any parameters that are not in the schema', () => {
    const currentParams = {
      max_tokens: 500,
      temperature: 0.8,
      top_p: 0.1,
      stop: 'text',
      new_parameter: 'new',
    }

    const expectParams = {
      max_tokens: 500,
      temperature: 0.8,
      top_p: 0.1,
      stop: 'text',
    }
    expect(validateAndFilterParameters(mockModelInputSchemaParameters, currentParams)).toEqual(expectParams)
  })

  it('removes a stop parameter if it is a blank string', () => {
    const currentParams = {
      max_tokens: 500,
      temperature: 0.8,
      top_p: 0.1,
      stop: '',
    }

    const expectParams = {
      max_tokens: 500,
      temperature: 0.8,
      top_p: 0.1,
    }
    expect(validateAndFilterParameters(mockModelInputSchemaParameters, currentParams)).toEqual(expectParams)

    const currentParams2 = {
      max_tokens: 500,
      temperature: 0.8,
      top_p: 0.1,
      stop: '    ',
    }
    expect(validateAndFilterParameters(mockModelInputSchemaParameters, currentParams2)).toEqual(expectParams)
  })

  it('removes any undefined values', () => {
    const currentParams = {
      max_tokens: 500,
      temperature: undefined,
      top_p: undefined,
      stop: 'text',
    }

    const expectParams = {
      max_tokens: 500,
      stop: 'text',
    }
    expect(validateAndFilterParameters(mockModelInputSchemaParameters, currentParams)).toEqual(expectParams)
  })
})

describe('hasDefaultParams', () => {
  it('returns true when the values of the current parameters are the same as the default', () => {
    const currentParams = {
      max_tokens: 4096,
      temperature: 1,
      top_p: 1,
      stop: [],
      presence_penalty: 0,
      frequency_penalty: 0,
    }

    const defaultParams = {
      max_tokens: 4096,
      temperature: 1,
      top_p: 1,
      stop: [],
    }

    expect(hasDefaultParams(currentParams, defaultParams)).toEqual(true)
  })

  it('returns false when the values of the current parameters are different from the default', () => {
    const defaultParams = {
      max_tokens: 4096,
      temperature: 1,
      top_p: 1,
      stop: [],
    }

    const currentParams = {
      max_tokens: 2048,
      temperature: 0.1,
      top_p: 0.1,
      stop: [],
    }

    expect(hasDefaultParams(defaultParams, currentParams)).toEqual(false)
  })
})

describe('getParameterSchema', () => {
  it('returns the parameter schema', () => {
    const defaultParams = {
      max_tokens: 2048,
      temperature: 0.8,
      top_p: 0.1,
      stop: undefined,
    }

    expect(getParameterSchema(mockModelInputSchemaParameters)).toEqual(defaultParams)
  })
})

describe('getModelState', () => {
  it('returns the default parameters for the model', () => {
    expect(
      getModelState({
        catalogData: mockModel,
        modelInputSchema: mockModelInputSchema,
        gettingStarted: mockGettingStarted,
      }),
    ).toEqual(mockModelState)
  })

  it('returns the model state with the prompt preset parameters', () => {
    const preset = mockPreset
    const {system_prompt, chat_prompt} = preset.parameters

    const modelInputSchema = {
      ...mockModelInputSchema,
      capabilities: {
        systemPrompt: true,
      },
    }

    const modelDetails = {
      ...mockModelDetails,
      modelInputSchema,
    }

    const result = getModelState(modelDetails, preset)

    const expected = {
      ...mockModelState,
      modelInputSchema,
      systemPrompt: system_prompt,
      chatInput: chat_prompt,
      parametersHasChanges: true,
    }

    expect(result).toEqual(expected)
  })

  it('combines the system prompt into the chat prompt if the model does not support system prompts', () => {
    const preset = mockPreset
    const {system_prompt, chat_prompt} = preset.parameters

    const modelInputSchema = {
      ...mockModelInputSchema,
      capabilities: {
        systemPrompt: false,
      },
    }

    const modelDetails = {
      ...mockModelDetails,
      modelInputSchema,
    }

    const result = getModelState(modelDetails, preset)

    const expected = {
      ...mockModelState,
      modelInputSchema,
      chatInput: `${system_prompt}\n${chat_prompt}`,
      parametersHasChanges: false,
    }

    expect(result).toEqual(expected)
  })
})

describe('combineParamsWithModel', () => {
  it('returns the default parameters', () => {
    const expected = {
      ...mockModelState,
      chatInput: mockChatInput,
    }

    expect(
      combineParamsWithModel({
        modelDetails: mockModelDetails,
        chatInputOverride: mockChatInput,
      }),
    ).toEqual(expected)
  })

  it('returns the combined parameters when keepParameters is true', () => {
    const expected = {
      ...mockModelState,
      parameters: mockNewParameters,
      parametersHasChanges: true,
      systemPrompt: mockNewSystemPrompt,
      chatInput: mockChatInput,
    }

    expect(
      combineParamsWithModel({
        modelDetails: mockModelDetails,
        systemPromptOverride: mockNewSystemPrompt,
        parametersOverride: mockNewParameters,
        chatInputOverride: mockChatInput,
      }),
    ).toEqual(expected)
  })

  it('returns the default parameters including the chat history when keepChatHistory is true', () => {
    const expected = {
      ...mockModelState,
      messages: mockNewMessages,
      chatInput: mockChatInput,
    }

    expect(
      combineParamsWithModel({
        modelDetails: mockModelDetails,
        messagesOverride: mockNewMessages,
        chatInputOverride: mockChatInput,
      }),
    ).toEqual(expected)
  })

  it('returns the combined parameters including the chat history when keepChatHistory and keepParameters are true', () => {
    const expected = {
      ...mockModelState,
      messages: mockNewMessages,
      parameters: mockNewParameters,
      parametersHasChanges: true,
      systemPrompt: mockNewSystemPrompt,
      chatInput: mockChatInput,
    }

    expect(
      combineParamsWithModel({
        modelDetails: mockModelDetails,
        systemPromptOverride: mockNewSystemPrompt,
        messagesOverride: mockNewMessages,
        parametersOverride: mockNewParameters,
        chatInputOverride: mockChatInput,
      }),
    ).toEqual(expected)
  })
})

describe('hasReachedMaxOutputTokens', () => {
  it('returns false when no max_tokens parameter is set and the model does not have a limit', () => {
    const tokenUsage = Object.assign({}, mockTokenUsage, {totalOutputTokens: 123})
    const maxTokensParam = Object.assign({}, mockModelIntegerInputSchemaParameter, {key: 'max_tokens'})
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {parameters: [maxTokensParam]})
    const model = Object.assign({}, mockModel, {max_output_tokens: null})
    const parameters: PlaygroundRequestParameters = {}
    const modelState = Object.assign({}, mockModelState, {catalogData: model, tokenUsage, modelInputSchema, parameters})

    expect(hasReachedMaxOutputTokens(modelState)).toEqual(false)
  })

  it('returns false when output tokens does not exceed model limit and max_tokens parameter is not set', () => {
    const tokenUsage = Object.assign({}, mockTokenUsage, {totalOutputTokens: 123})
    const maxTokensParam = Object.assign({}, mockModelIntegerInputSchemaParameter, {key: 'max_tokens'})
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {parameters: [maxTokensParam]})
    const model = Object.assign({}, mockModel, {max_output_tokens: 456})
    const parameters: PlaygroundRequestParameters = {}
    const modelState = Object.assign({}, mockModelState, {catalogData: model, tokenUsage, modelInputSchema, parameters})

    expect(hasReachedMaxOutputTokens(modelState)).toEqual(false)
  })

  it('returns false when output tokens does not exceed max_tokens parameter value and model does not have a limit', () => {
    const tokenUsage = Object.assign({}, mockTokenUsage, {totalOutputTokens: 123})
    const maxTokensParam = Object.assign({}, mockModelIntegerInputSchemaParameter, {key: 'max_tokens'})
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {parameters: [maxTokensParam]})
    const model = Object.assign({}, mockModel, {max_output_tokens: null})
    const parameters: PlaygroundRequestParameters = {max_tokens: 456}
    const modelState = Object.assign({}, mockModelState, {catalogData: model, tokenUsage, modelInputSchema, parameters})

    expect(hasReachedMaxOutputTokens(modelState)).toEqual(false)
  })

  it('returns true when output tokens exceeds model limit even when max_tokens parameter is not set', () => {
    const tokenUsage = Object.assign({}, mockTokenUsage, {totalOutputTokens: 123})
    const maxTokensParam = Object.assign({}, mockModelIntegerInputSchemaParameter, {key: 'max_tokens'})
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {parameters: [maxTokensParam]})
    const model = Object.assign({}, mockModel, {max_output_tokens: 50})
    const parameters: PlaygroundRequestParameters = {}
    const modelState = Object.assign({}, mockModelState, {catalogData: model, tokenUsage, modelInputSchema, parameters})

    expect(hasReachedMaxOutputTokens(modelState)).toEqual(true)
  })

  it('returns true when output tokens exceeds max_tokens parameter value even when model does not have a limit', () => {
    const tokenUsage = Object.assign({}, mockTokenUsage, {totalOutputTokens: 123})
    const maxTokensParam = Object.assign({}, mockModelIntegerInputSchemaParameter, {key: 'max_tokens'})
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {parameters: [maxTokensParam]})
    const model = Object.assign({}, mockModel, {max_output_tokens: null})
    const parameters: PlaygroundRequestParameters = {max_tokens: 50}
    const modelState = Object.assign({}, mockModelState, {catalogData: model, tokenUsage, modelInputSchema, parameters})

    expect(hasReachedMaxOutputTokens(modelState)).toEqual(true)
  })

  it('returns true when output tokens exceeds max_tokens parameter value even when within the model limit', () => {
    const tokenUsage = Object.assign({}, mockTokenUsage, {totalOutputTokens: 123})
    const maxTokensParam = Object.assign({}, mockModelIntegerInputSchemaParameter, {key: 'max_tokens'})
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {parameters: [maxTokensParam]})
    const model = Object.assign({}, mockModel, {max_output_tokens: 456})
    const parameters: PlaygroundRequestParameters = {max_tokens: 50}
    const modelState = Object.assign({}, mockModelState, {catalogData: model, tokenUsage, modelInputSchema, parameters})

    expect(hasReachedMaxOutputTokens(modelState)).toEqual(true)
  })

  it('returns true when output tokens exceeds max_tokens parameter value and model limit', () => {
    const tokenUsage = Object.assign({}, mockTokenUsage, {totalOutputTokens: 123})
    const maxTokensParam = Object.assign({}, mockModelIntegerInputSchemaParameter, {key: 'max_tokens'})
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {parameters: [maxTokensParam]})
    const model = Object.assign({}, mockModel, {max_output_tokens: 75})
    const parameters: PlaygroundRequestParameters = {max_tokens: 50}
    const modelState = Object.assign({}, mockModelState, {catalogData: model, tokenUsage, modelInputSchema, parameters})

    expect(hasReachedMaxOutputTokens(modelState)).toEqual(true)
  })
})

describe('getMostRecentUserMessage', () => {
  it('returns the most recent user message', () => {
    const messages: PlaygroundMessage[] = [
      {role: 'user', timestamp: new Date(), message: 'user message 1'},
      {role: 'assistant', timestamp: new Date(), message: 'assistant message 1'},
      {role: 'user', timestamp: new Date(), message: 'user message 2'},
      {role: 'assistant', timestamp: new Date(), message: 'assistant message 2'},
    ]

    expect(getMostRecentUserMessage(messages)).toEqual('user message 2')
  })
})
