import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {MessageContent, PresetPayload} from '../types'

export async function createPreset({preset}: {preset: PresetPayload}): Promise<Response> {
  const response = await verifiedFetchJSON(`/marketplace/models/presets`, {
    method: 'POST',
    body: {
      preset,
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

  const response = await verifiedFetchJSON(`/marketplace/models/presets/${encodedUrlIdentifier}`, {
    method: 'PUT',
    body: {
      preset,
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

export const isValidString = (s: string) => s.trim() !== ''

export const getTextFromMessage = (messageContent: MessageContent = ''): string | undefined => {
  const message =
    typeof messageContent === 'string'
      ? messageContent
      : messageContent
          .reduce((acc, msg) => {
            if (msg.type === 'text') return [...acc, msg.text]
            return acc
          }, [] as string[])
          .join('\n')

  return isValidString(message) ? message.trim() : undefined
}
