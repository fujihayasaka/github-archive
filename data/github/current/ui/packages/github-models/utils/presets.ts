import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {ModelDetails, PlaygroundResponseFormat, Preset, PresetPayload} from '../types'
import {combineParamsWithModel} from './model-state'
import {setPlaygroundLocalStorageMessages} from './playground-local-storage'

export async function createPreset({preset}: {preset: PresetPayload}): Promise<Response> {
  const {conversationHistory, ...otherPresetParams} = preset

  const response = await verifiedFetchJSON(`/marketplace/models/presets`, {
    method: 'POST',
    body: {
      preset: {
        ...otherPresetParams,
        conversation_history: conversationHistory,
      },
    },
  })
  return response
}

export async function updatePreset({
  urlIdentifier,
  preset,
}: {
  urlIdentifier: string
  preset: PresetPayload
}): Promise<Response> {
  const encodedUrlIdentifier = encodeURIComponent(urlIdentifier)

  const {conversationHistory, ...otherPresetParams} = preset

  const response = await verifiedFetchJSON(`/marketplace/models/presets/${encodedUrlIdentifier}`, {
    method: 'PUT',
    body: {
      preset: {
        ...otherPresetParams,
        conversation_history: conversationHistory,
      },
    },
  })
  return response
}

export async function deletePreset({urlIdentifier}: {urlIdentifier: string}): Promise<Response> {
  const encodedUrlIdentifier = encodeURIComponent(urlIdentifier)
  const response = await verifiedFetchJSON(`/marketplace/models/presets/${encodedUrlIdentifier}`, {
    method: 'DELETE',
  })
  if (response.ok) {
    return response
  } else {
    throw new Error('Failed to delete preset')
  }
}

/**
 * Presets can be applied to any model, so we want to make sure that the params provided
 * are valid for the model they are being applied to.
 */
export function getModelStateFromPreset(preset: Preset, modelDetails: ModelDetails) {
  const {parameters: presetParameters, conversationHistory = []} = preset
  const {response_format: responseFormat = 'text', system_prompt: systemPrompt = '', ...parameters} = presetParameters

  // we know response_format is always a PlaygroundResponseFormat, but TS doesn't
  const responseFormatOverride = responseFormat as PlaygroundResponseFormat

  const messages = conversationHistory.map(message => ({
    ...message,
    timestamp: new Date(message.timestamp),
  }))

  setPlaygroundLocalStorageMessages({messages, modelName: modelDetails.catalogData.name})

  // We always want the chat history and params to be applied from the preset
  return combineParamsWithModel({
    modelDetails,
    systemPromptOverride: String(systemPrompt),
    responseFormatOverride,
    messagesOverride: messages,
    parametersOverride: parameters,
    chatInputOverride: '',
  })
}
