import {sendEvent} from '@github-ui/hydro-analytics'
import {logError} from './console'

type Json = string | number | boolean | null | {[property: string]: Json} | Json[]

type JsonRoot = {[property: string]: Json}

export type GraphQLError = {type: string; message: string; path: Array<string | number>}

export type GraphQLSuccessfulResult = {
  data: JsonRoot
  timestamp?: number
  extensions?: Record<string, Record<string, JsonRoot>>
}

export type GraphQLErrorResult = {
  errors: GraphQLError[]
  data?: JsonRoot
  timestamp?: number
  extensions: Record<string, string>
}

export type GraphQLResult = GraphQLSuccessfulResult | GraphQLErrorResult

/**
 * SAML errors are due to the user not being SSO'd to an org from which some data was returned. Just let the app handle
 * this.
 */
export const ALLOWED_ERRORS = ['SAML']
/**
 * For some specific errors + messages, we want to allow them in certain contexts and let the app handle them
 */
export const CONDITIONAL_ALLOWED_ERRORS: Record<string, string[]> = {
  FORBIDDEN: ['SAML error'],
}

/**
 * Remove SAML-related errors - they don't necessarily prevent data from being returned if certain items
 * were filtered out of a list for example.
 */
function removeAllowedErrors(decoded: GraphQLResult): GraphQLResult {
  if ('errors' in decoded) {
    return {
      ...decoded,
      errors: decoded.errors.filter(
        error =>
          !ALLOWED_ERRORS.includes(error.type) && !CONDITIONAL_ALLOWED_ERRORS[error.type]?.includes(error.message),
      ),
    }
  }

  return decoded
}

export function validateGraphQL(decoded: GraphQLResult, requestId: string): decoded is GraphQLSuccessfulResult {
  decoded = removeAllowedErrors(decoded)
  if ('errors' in decoded && decoded.errors.length) {
    const errorMessage = decoded.errors
      .map(error => `${error.message}${error.path ? ` (path: ${error.path})` : ''}`)
      .join(', ')

    sendEvent('dotcom_chat.error', {type: 'execution', nodeType: 'graphql', mode: 'pipes', errorMessage})
    throw new Error(errorMessage)
  }

  if (!('data' in decoded)) {
    const errorMessage = `Expected data property in response: ${JSON.stringify(decoded)}. requestId: ${requestId}`
    logError(errorMessage)
    sendEvent('dotcom_chat.error', {type: 'execution', nodeType: 'graphql', mode: 'pipes', errorMessage})
    throw new Error('Failed to fetch data.')
  }

  return true
}
