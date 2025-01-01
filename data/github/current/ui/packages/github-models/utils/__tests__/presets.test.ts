import {createPreset, updatePreset, deletePreset, isValidString, getTextFromMessage} from '../presets'
import {mockPreset} from '../../routes/playground/__tests__/mocks'
import type {MessageContent, TextInputs} from '../../types'

const mockVerifiedFetchJSON = jest.fn()
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
}))

describe('createPreset', () => {
  it('returns response from create endpoint', async () => {
    const {urlIdentifier, ...presetPayload} = mockPreset
    const expectedResponse = {ok: true, json: () => mockPreset}

    mockVerifiedFetchJSON.mockResolvedValue(expectedResponse)

    await expect(createPreset({preset: presetPayload})).resolves.toEqual(expectedResponse)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets', {
      method: 'POST',
      body: {
        preset: presetPayload,
      },
    })
  })
})

describe('updatePreset', () => {
  it('returns response from update endpoint', async () => {
    const {urlIdentifier, ...presetPayload} = mockPreset
    const encodedUrlIdentifier = encodeURIComponent(urlIdentifier)
    const expectedResponse = {ok: true, json: () => mockPreset}

    mockVerifiedFetchJSON.mockResolvedValue(expectedResponse)

    await expect(updatePreset({urlIdentifier, preset: presetPayload})).resolves.toEqual(expectedResponse)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`/marketplace/models/presets/${encodedUrlIdentifier}`, {
      method: 'PUT',
      body: {
        preset: presetPayload,
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

describe('isValidString', () => {
  it('returns true for valid string', () => {
    expect(isValidString('test')).toBe(true)
  })

  it('returns false for empty string', () => {
    expect(isValidString('')).toBe(false)
  })

  it('returns false for string with only whitespace', () => {
    expect(isValidString('  ')).toBe(false)
  })
})

describe('getTextFromMessage', () => {
  it('returns text from MessageContent TextInputs message', () => {
    const textInput1: TextInputs = {
      type: 'text',
      text: 'Hello, my name is',
    }
    const textInput2: TextInputs = {
      type: 'text',
      text: 'Mona',
    }
    const mmc: MessageContent = [textInput1, textInput2]

    expect(getTextFromMessage(mmc)).toBe('Hello, my name is\nMona')
  })

  it('returns trimmed text from string message', () => {
    expect(getTextFromMessage('Hello')).toBe('Hello')
    expect(getTextFromMessage('Hello      ')).toBe('Hello')
    expect(getTextFromMessage('      Hello')).toBe('Hello')
  })

  it('returns undefined for empty message', () => {
    expect(getTextFromMessage('')).toBe(undefined)
    expect(getTextFromMessage('    ')).toBe(undefined)
    expect(getTextFromMessage()).toBe(undefined)
  })
})
