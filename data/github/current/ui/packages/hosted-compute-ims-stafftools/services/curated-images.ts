import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {manageCuratedImagesUrl, manageCuratedImageVersionUrl, manageCuratedPointersUrl} from '../helpers/urls'
import type {
  CreateCuratedImagePayload,
  CreateCuratedImagePointerPayload,
  UpdateCuratedImagePayload,
  UpdateCuratedImagePointerPayload,
  UpdateCuratedImageVersionPayload,
  DeleteCuratedImagePayload,
  DeleteCuratedImageVersionPayload,
} from '../types/types'

type HttpMethod = 'POST' | 'PUT' | 'DELETE' | 'GET'

type RequestResponse<T> = {
  ok: boolean
  error: string
  statusCode: number
  statusText: string
  body: T | null
}

type RequestResponseBodyError = {
  error?: {
    message?: string
  }
}

const request = async <T>(url: string, method: HttpMethod, body: unknown): Promise<RequestResponse<T>> => {
  const response = await verifiedFetchJSON(url, {
    method,
    body,
  })

  let responseBody: unknown = ''
  try {
    responseBody = await response.json()
  } catch (error: unknown) {
    return {
      ok: false,
      statusCode: response.status,
      statusText: response.statusText,
      error: `Failed to parse response body: ${(error as Error)?.message}`,
      body: null,
    }
  }

  const ok = response.status === 200 || response.status === 303
  const error = ok ? '' : (responseBody as RequestResponseBodyError)?.error?.message ?? ''

  return {
    ok,
    statusCode: response.status,
    statusText: response.statusText,
    error,
    body: responseBody as T,
  }
}

export const createCuratedImageDefinition = async (payload: CreateCuratedImagePayload) => {
  return await request(manageCuratedImagesUrl(), 'POST', payload)
}

export const updateCuratedImageDefinition = async (payload: UpdateCuratedImagePayload) => {
  return await request(manageCuratedImagesUrl(), 'PUT', payload)
}

export const deleteCuratedImageDefinition = async (payload: DeleteCuratedImagePayload) => {
  return await request(manageCuratedImagesUrl(), 'DELETE', payload)
}

export const updateCuratedImageVersion = async (payload: UpdateCuratedImageVersionPayload) => {
  return await request(manageCuratedImageVersionUrl(), 'PUT', payload)
}

export const deleteCuratedImageVersion = async (payload: DeleteCuratedImageVersionPayload) => {
  return await request(manageCuratedImageVersionUrl(), 'DELETE', payload)
}

export const createCuratedImageDefinitionPointer = async (payload: CreateCuratedImagePointerPayload) => {
  return await request(manageCuratedPointersUrl(), 'POST', payload)
}

export const updateCuratedImageDefinitionPointer = async (payload: UpdateCuratedImagePointerPayload) => {
  return await request(manageCuratedPointersUrl(), 'PUT', payload)
}

export const deleteCuratedImageDefinitionPointer = async (payload: DeleteCuratedImagePayload) => {
  return await request(manageCuratedPointersUrl(), 'DELETE', payload)
}
