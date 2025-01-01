import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {
  createExemptionRequestPayload,
  getApproversRequestPayload,
  updateExemptionRequestPayload,
  BypassActor,
  SimpleRepository,
} from '../delegated-bypass-types'

type Response<T = void> = {statusCode: number; error?: string} & T

export const createExemptionRequest = async (url: string, payload: createExemptionRequestPayload) => {
  return request<createExemptionRequestPayload, {request_number: number; redirect_uri?: string; expires_at?: string}>(
    url,
    'POST',
    payload,
  )
}

export const updateExemptionRequest = async (url: string, payload: updateExemptionRequestPayload) => {
  return request<updateExemptionRequestPayload>(url, 'PUT', payload)
}

export const getApprovers = async (url: string, payload?: getApproversRequestPayload) =>
  request<getApproversRequestPayload, {approvers: BypassActor[]}>(url, 'GET', payload)

async function request<T = unknown, U = unknown>(url: string, method: string, body?: T): Promise<Response<U>> {
  let query = ''
  if (body && method === 'GET') {
    query = new URLSearchParams(body).toString()
    body = undefined
  }
  const response = await verifiedFetchJSON(`${url}?${query}`, {method, body})
  const data = await response.json()
  return {...data, statusCode: response.status}
}

export const getRepoSuggestionsForOrg = async (
  url: string,
  {query, excludePublicRepos}: {query: string; excludePublicRepos: boolean},
): Promise<SimpleRepository[]> => {
  const response = await verifiedFetchJSON(
    `${url}?q=${encodeURIComponent(query)}&excludePublicRepos=${excludePublicRepos ? 'true' : 'false'}`,
    {method: 'GET'},
  )
  return await response.json()
}
