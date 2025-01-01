import {createPreset, updatePreset, deletePreset, getModelStateFromPreset} from '../presets'
import {mockModelDetails, mockPreset} from '../../routes/playground/__tests__/mocks'
import type {PlaygroundRequestParameters} from '../../types'

const mockVerifiedFetchJSON = jest.fn()
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
}))

describe('createPreset', () => {
  it('returns response from create endpoint', async () => {
    const {urlIdentifier, ...presetPayload} = mockPreset
    const {conversationHistory, ...otherPresetParams} = presetPayload
    const expectedResponse = {ok: true, json: () => mockPreset}

    mockVerifiedFetchJSON.mockResolvedValue(expectedResponse)

    await expect(createPreset({preset: presetPayload})).resolves.toEqual(expectedResponse)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets', {
      method: 'POST',
      body: {
        preset: {
          ...otherPresetParams,
          conversation_history: conversationHistory,
        },
      },
    })
  })
})

describe('updatePreset', () => {
  it('returns response from update endpoint', async () => {
    const {urlIdentifier, ...presetPayload} = mockPreset
    const {conversationHistory, ...otherPresetParams} = presetPayload
    const encodedUrlIdentifier = encodeURIComponent(urlIdentifier)
    const expectedResponse = {ok: true, json: () => mockPreset}

    mockVerifiedFetchJSON.mockResolvedValue(expectedResponse)

    await expect(updatePreset({urlIdentifier, preset: presetPayload})).resolves.toEqual(expectedResponse)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`/marketplace/models/presets/${encodedUrlIdentifier}`, {
      method: 'PUT',
      body: {
        preset: {
          ...otherPresetParams,
          conversation_history: conversationHistory,
        },
      },
    })
  })
})

describe('deletePreset', () => {
  it('returns response from delete endpoint', async () => {
    const {urlIdentifier} = mockPreset
    const encodedUrlIdentifier = encodeURIComponent(urlIdentifier)
    const expectedResponse = {ok: true}

    mockVerifiedFetchJSON.mockResolvedValue(expectedResponse)

    await expect(deletePreset({urlIdentifier})).resolves.toEqual(expectedResponse)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`/marketplace/models/presets/${encodedUrlIdentifier}`, {
      method: 'DELETE',
    })
  })

  it('throws an error if response from delete endpoint is not ok', async () => {
    const {urlIdentifier} = mockPreset
    const encodedUrlIdentifier = encodeURIComponent(urlIdentifier)
    const errorResponse = new Error('Failed to delete preset')

    mockVerifiedFetchJSON.mockRejectedValue(errorResponse)

    await expect(deletePreset({urlIdentifier})).rejects.toThrow(errorResponse)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`/marketplace/models/presets/${encodedUrlIdentifier}`, {
      method: 'DELETE',
    })
  })
})

describe('getModelStateFromPreset', () => {
  it('returns the model state with the preset parameters', () => {
    const preset = mockPreset
    const {system_prompt, ...parameters} = preset.parameters
    const modelDetails = mockModelDetails

    const result = getModelStateFromPreset(preset, modelDetails)

    expect(result.parameters).toEqual(parameters)
    expect(result.systemPrompt).toEqual(system_prompt)
    expect(result.messages).toEqual(preset.conversationHistory)
    expect(result.chatInput).toEqual('')
  })

  it('filters out any preset parameters that are not in the model input schema', () => {
    const preset = {
      ...mockPreset,
      parameters: {
        ...mockPreset.parameters,
        invalid_parameter: 'invalid',
      } as PlaygroundRequestParameters,
    }
    const {system_prompt, ...parameters} = preset.parameters
    const modelDetails = mockModelDetails

    const result = getModelStateFromPreset(preset, modelDetails)

    expect(result.parameters).toEqual(parameters)
    expect(result.systemPrompt).toEqual(system_prompt)
  })
})
