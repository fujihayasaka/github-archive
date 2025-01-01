import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {useRef} from 'react'
import safeStorage from '@github-ui/safe-storage'

const safeLocalStorage = safeStorage('localStorage')

/**
 * Status of a Copilot API request
 */
export type CopilotRequestStatus = 'success' | 'error' | 'loading' | 'idle'

/**
 * API endpoint configurations
 */
export const COPILOT_API_ENDPOINTS = {
  // For local development
  local: 'http://localhost:2206/agents/github-classifier',
  // For production use
  production: 'https://api.githubcopilot.com/agents/github-classifier',
}

/**
 * Hook to create and manage a Copilot auth token provider
 */
export function useCopilotAuth() {
  return useRef(new CopilotAuthTokenProvider([]))
}

/**
 * Get standardized headers for Copilot API requests
 */
export function getCopilotRequestHeaders(token: {authorizationHeaderValue: string}) {
  return {
    Authorization: token.authorizationHeaderValue,
    'copilot-integration-id': 'copilot-embedded-experience',
    'Content-Type': 'application/json',
  }
}

/**
 * Parse a Copilot API response
 *
 * @param response - The fetch response from the Copilot API
 * @returns Parsed JSON content or null if parsing fails
 */
export async function parseCopilotResponse(response: Response) {
  if (!response.ok) return null

  try {
    const text = await response.text()
    const firstLine = text.split('\n')[0]?.substring(6)
    if (!firstLine) return null

    return JSON.parse(JSON.parse(firstLine).choices[0].message.content)
  } catch {
    return null
  }
}

/**
 * Create a Copilot API request
 *
 * @param token - Auth token
 * @param prompt - The prompt to send to Copilot
 * @param references - References to include in the request
 * @returns Promise resolving to parsed results or null
 */
export async function createCopilotRequest(
  token: {authorizationHeaderValue: string},
  prompt: string,
  references: Array<Record<string, unknown>>,
) {
  // Use local endpoint for development; change to production for deployment
  const endpoint = COPILOT_API_ENDPOINTS.production

  const requestBody = {
    messages: [
      {
        role: 'user',
        content: prompt,
        copilot_references: references,
      },
    ],
  }

  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      mode: 'cors',
      cache: 'no-cache',
      headers: getCopilotRequestHeaders(token),
      body: JSON.stringify(requestBody),
    })

    return await parseCopilotResponse(response)
  } catch {
    return null
  }
}

export const userRejectedCopilotTypeSuggestion = (issueId: string): boolean => {
  return safeLocalStorage.getItem(`copilot-suggested-type-dismiss/${issueId}`) === 'true'
}

export const userRejectedCopilotLabelsSuggestion = (issueId: string): boolean => {
  return safeLocalStorage.getItem(`copilot-suggested-labels-dismiss/${issueId}`) === 'true'
}

export const setUserRejectedCopilotTypeSuggestion = (issueId: string): void => {
  safeLocalStorage.setItem(`copilot-suggested-type-dismiss/${issueId}`, 'true')
}

export const setUserRejectedCopilotLabelsSuggestion = (issueId: string): void => {
  safeLocalStorage.setItem(`copilot-suggested-labels-dismiss/${issueId}`, 'true')
}
