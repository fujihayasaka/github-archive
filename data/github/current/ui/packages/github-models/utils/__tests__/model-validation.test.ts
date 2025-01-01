import {
  mockGettingStarted,
  mockModel,
  mockModelInputSchema,
  mockModelInputSchemaParameters,
  mockModelDetails,
  mockModelState,
  mockNewMessages,
  mockNewParameters,
  mockNewSystemPrompt,
  mockChatInput,
} from '../../routes/playground/__tests__/mocks'
import {
  getModelStateDefaults,
  combineParamsWithModel,
  getParameterSchema,
  hasDefaultParams,
  validateAndFilterParameters,
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

describe('getModelStateDefaults', () => {
  it('returns the default parameters for the model', () => {
    expect(
      getModelStateDefaults({
        catalogData: mockModel,
        modelInputSchema: mockModelInputSchema,
        gettingStarted: mockGettingStarted,
      }),
    ).toEqual(mockModelState)
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
