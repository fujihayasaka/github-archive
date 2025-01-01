import type {
  MessageContent,
  ModelDetails,
  ModelInputSchema,
  ModelInputSchemaParameter,
  ModelParameterValue,
  ModelState,
  PlaygroundMessage,
  PlaygroundRequestParameters,
  PlaygroundResponseFormat,
  Preset,
  UsageStats,
} from '../types'
import {PlaygroundAPIMessageAuthorValuesUser} from '../types'
import {getDefaultTokenUsage} from './model-usage'

export const defaultResponseFormat: PlaygroundResponseFormat = 'text'

/**
 * This validates the parameters based on the schema provided by the model
 * It ensures that the values are of the correct type and within the acceptable range,
 * and removes any parameters that are not in the schema
 * @param schemaParams The input schema for the model to validate the values against
 * @param currentParams The current parameters to validate
 * @returns The validated parameters
 */
export const validateAndFilterParameters = (
  schemaParams: ModelInputSchemaParameter[],
  currentParams: PlaygroundRequestParameters,
) =>
  schemaParams.reduce(
    (acc: Record<string, ModelParameterValue>, schema: ModelInputSchemaParameter) => {
      const {key} = schema
      const value = currentParams[key]
      const validatedValue = validateByKey(key, validateByType(schema, value))

      // If the value is undefined, it means it is not valid, so we remove it from the parameters
      if ([value, validatedValue].includes(undefined)) return acc

      return {
        ...acc,
        [key]: validatedValue,
      }
    },
    {} as Record<string, ModelParameterValue>,
  )

/**
 * This validates the system prompt if it's allowed by the model schema
 * @param modelInputSchema The input schema for the model to validate the system prompt against
 * @param systemPrompt The current system prompt
 * @returns The system prompt, or null if it's not allowed by the schema
 */
export const validateSystemPrompt = (modelInputSchema: ModelInputSchema, systemPrompt: string): string | null =>
  modelInputSchema?.capabilities?.systemPrompt ? systemPrompt : null

/**
 * Validates the value based on the type of the schema
 * @param schema The input schema for the model to validate the value against
 * @param value The value to validate
 * @returns The validated value
 */
export const validateByType = (schema: ModelInputSchemaParameter, value: ModelParameterValue) => {
  const {type, min = -Infinity, max = Infinity, default: def = ''} = schema

  switch (type) {
    case 'number':
    case 'integer': {
      const num = [value, def, 0].find(v => !isNaN(parseFloat(v as string))) as number
      return Math.max(Math.min(num, max), min)
    }
    default:
      return value
  }
}

/**
 * Validates the value based on the key of the schema
 * @param key The key of the schema to validate the value against
 * @param value The value to validate
 * @returns The validated value
 */
/* eslint-disable-next-line @typescript-eslint/no-explicit-any */
const validateByKey = (key: string, value: any) => {
  switch (key) {
    case 'stop': // Can be Array, string, or undefined. Blank strings are invalid.
      return typeof value === 'string' && value.trim() === '' ? undefined : value
    default:
      return value
  }
}

export const hasDefaultParams = (
  newParamsSet: PlaygroundRequestParameters,
  defaultParamsSet: PlaygroundRequestParameters,
) => {
  return Object.entries(defaultParamsSet).every(([key, value]) => {
    return newParamsSet[key] === value || (Array.isArray(newParamsSet[key]) && newParamsSet[key].length === 0)
  })
}

export const getParameterSchema = (parameters: ModelInputSchemaParameter[] = []) =>
  parameters.reduce(
    (acc, parameter) => ({
      ...acc,
      [parameter.key]: parameter.default,
    }),
    {} as PlaygroundRequestParameters,
  )

/**
 * Gets the default state for a model based on the model details, with optional prompt preset
 * @param modelDetails The details of the model
 * @param preset The preset to apply, if any
 * @returns The default model state, with any provided preset applied
 */
export const getModelState = (modelDetails: ModelDetails, preset?: Preset): ModelState => {
  const defaultModelState = getModelStateDefaults(modelDetails)

  if (preset) {
    const {parameters = {}} = preset
    // Not all models support system prompts, in which case we add the system prompt to the chat input
    const canHaveSystemPrompt = modelDetails.modelInputSchema?.capabilities?.systemPrompt

    const systemPrompt = String(parameters.system_prompt || '')
    const chatInput = String(parameters.chat_prompt || '')

    const systemPromptOverride = canHaveSystemPrompt ? systemPrompt : ''
    const chatInputOverride = canHaveSystemPrompt ? chatInput : `${systemPrompt}\n${chatInput}`

    return combineParamsWithModel({
      modelDetails,
      systemPromptOverride,
      chatInputOverride,
    })
  }
  return defaultModelState
}

/**
 * Gets the default state for a model based on the model details
 */
const getModelStateDefaults = ({catalogData, modelInputSchema, gettingStarted}: ModelDetails): ModelState => ({
  catalogData,
  modelInputSchema,
  gettingStarted,
  messages: [],
  isLoading: false,
  systemPrompt: '',
  isUseIndexSelected: false,
  chatInput: '',
  responseFormat: 'text',
  jsonSchema: '',
  chatClosed: false,
  parameters: getParameterSchema(modelInputSchema?.parameters),
  parametersHasChanges: false,
  tokenUsage: getDefaultTokenUsage(),
  usageStats: getDefaultUsageStats(),
})

/**
 * Gets the default parameters from the model, and applies the provided values over top
 * @param modelDetails The details of the model
 * @param systemPromptOverride The system prompt to use, if any
 * @param responseFormatOverride The response format to use, if any
 * @param jsonSchemaOverride The JSON schema to use, if any
 * @param messagesOverride The messages to use, if any
 * @param parametersOverride The parameters to use, if any
 * @param chatInputOverride The chat input to use, if any
 * @returns The default model state, with any provided overrides applied
 */
export const combineParamsWithModel = ({
  modelDetails,
  systemPromptOverride = '',
  responseFormatOverride = 'text',
  jsonSchemaOverride = '',
  messagesOverride,
  parametersOverride = {},
  chatInputOverride,
}: {
  modelDetails: ModelDetails
  systemPromptOverride?: string
  responseFormatOverride?: PlaygroundResponseFormat
  jsonSchemaOverride?: string
  messagesOverride?: PlaygroundMessage[]
  parametersOverride?: PlaygroundRequestParameters
  chatInputOverride?: MessageContent
}): ModelState => {
  const defaultModelState = getModelStateDefaults(modelDetails)
  const promptOverrideIsSet = systemPromptOverride.trim() !== ''
  // We need to set the parameters before we check if they have changes
  const parameters = {...defaultModelState.parameters, ...parametersOverride}
  const parametersHasChanges = promptOverrideIsSet || !hasDefaultParams(parameters, defaultModelState.parameters)
  // Now set the rest of the overrides
  const systemPrompt = promptOverrideIsSet ? systemPromptOverride : defaultModelState.systemPrompt
  const messages = messagesOverride ?? defaultModelState.messages
  const chatInput = chatInputOverride ?? defaultModelState.chatInput
  const responseFormat = responseFormatOverride ?? defaultModelState.responseFormat
  const jsonSchema = jsonSchemaOverride ?? defaultModelState.jsonSchema

  return {
    ...defaultModelState,
    systemPrompt,
    responseFormat,
    jsonSchema,
    chatInput,
    parameters,
    parametersHasChanges,
    messages,
  }
}

export const getDefaultUsageStats = (): UsageStats => ({
  lastMessageLatency: 0,
  totalLatency: 0,
})

export const getMaxOutputTokensParameterValue = (
  modelInputSchema: ModelInputSchema | undefined,
  parameters: PlaygroundRequestParameters,
): number | undefined => {
  const paramSchema = modelInputSchema?.parameters?.find(p => p.key === 'max_tokens' && p.type === 'integer')
  if (!paramSchema) return
  const value = parameters[paramSchema.key]
  if (!value) return
  return parseInt(value, 10)
}

export const getMostRecentUserMessageTimestamp = (messages: PlaygroundMessage[]) => {
  const userMessages = messages.filter(msg => msg.role === PlaygroundAPIMessageAuthorValuesUser)
  if (userMessages.length < 1) return

  const latestTime = Math.max(...userMessages.map(msg => msg.timestamp.getTime()))
  return new Date(latestTime)
}

export const getMostRecentUserMessage = (messages: PlaygroundMessage[]) => {
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i]?.role === PlaygroundAPIMessageAuthorValuesUser) return messages[i]?.message
  }
}

export const hasReachedMaxOutputTokens = ({
  catalogData,
  modelInputSchema,
  parameters,
  tokenUsage,
}: Pick<ModelState, 'catalogData' | 'modelInputSchema' | 'parameters' | 'tokenUsage'>) => {
  const maxModelOutputTokens = catalogData.max_output_tokens
  const maxParamOutputTokens = getMaxOutputTokensParameterValue(modelInputSchema, parameters)
  const {totalOutputTokens} = tokenUsage
  if (maxModelOutputTokens !== null && totalOutputTokens >= maxModelOutputTokens) {
    return true
  }
  if (maxParamOutputTokens !== undefined && totalOutputTokens >= maxParamOutputTokens) {
    return true
  }
  return false
}
