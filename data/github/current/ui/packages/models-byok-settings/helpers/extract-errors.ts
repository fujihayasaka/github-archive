import {isResponseError} from '@github-ui/react-core/future/response-error'

export async function getErrorMessageFromResponse(error: unknown) {
  let message: string | null = null
  if (isResponseError(error)) {
    try {
      // We need to clone the response because they can only be read once.
      // and we don't know if somebody else has already read it.
      const response = error.response.clone()
      const json = await response.json()
      if (typeof json.message === 'string') {
        message = json.message
      }
    } catch {
      // Empty on purpose
    }
  }
  return message
}
