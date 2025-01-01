import {PlaygroundAPIMessageAuthorValues, type PlaygroundMessage} from '../../../types'

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function isPlaygroundMessage(obj: any): obj is PlaygroundMessage {
  return (
    typeof obj === 'object' &&
    obj !== null &&
    typeof obj.timestamp === 'string' &&
    typeof obj.role === 'string' &&
    typeof obj.message === 'string' &&
    PlaygroundAPIMessageAuthorValues.includes(obj.role)
  )
}

export function validateJSONAsPlaygroundMessages(input: string): PlaygroundMessage[] | null {
  try {
    const parsed = JSON.parse(input)
    if (Array.isArray(parsed) && parsed.every(isPlaygroundMessage)) {
      let parsedAndValidated = parsed
      // Make sure dates are parsed
      parsedAndValidated = parsedAndValidated.map(message => ({
        ...message,
        timestamp: new Date(message.timestamp),
      }))
      return parsedAndValidated
    }
    return null
  } catch {
    return null
  }
}

export const isValidPlaygroundMessageJSON = (input: string): boolean => {
  try {
    return validateJSONAsPlaygroundMessages(input) !== null
  } catch {
    return false
  }
}
