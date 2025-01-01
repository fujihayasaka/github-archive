import {ERROR_MSG, ERRORS_BY_STATUS} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {
  APIResult,
  CustomCopilotId,
  CustomCopilotPayload,
  FailedAPIResult,
  IndexCustomCopilot,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {customCopilotApiPath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

const urlPathPrefix = '/github-copilot/chat'

export const CUSTOM_COPILOTS_QUERY_KEY = ['copilot-chat', 'custom-copilots']

export function customCopilotQueryKey(id: CustomCopilotId | null) {
  if (!id) {
    return ['copilot-chat', 'custom-copilot', null]
  }
  return ['copilot-chat', 'custom-copilot', {id: id.id, owner: id.owner}]
}

export interface VisibilitySettings {
  memberCount: number | null
}

export async function fetchCustomCopilots(): Promise<IndexCustomCopilot[]> {
  const res = await verifiedFetchJSON(`${urlPathPrefix}/custom_copilots`)
  if (!res.ok) throw new Error(`Failed to fetch spaces: ${ERRORS_BY_STATUS[res.status] || ERROR_MSG}`)
  const payload = await res.json()
  return payload
}

export async function fetchCustomCopilot(
  customCopilotID: CustomCopilotId | null,
): Promise<APIResult<CustomCopilotPayload>> {
  // This should never run because we're setting
  // the enabled property to false in the useQuery call that uses it
  if (!customCopilotID) {
    return {status: 500, ok: false, error: 'unexpected null custom copilot id'}
  }
  let url: string
  const {owner, id} = customCopilotID
  if (owner) {
    url = `${urlPathPrefix}/custom_copilots/${owner}/${id}`
  } else {
    url = `${urlPathPrefix}/custom_copilots/${id}`
  }
  const res = await verifiedFetchJSON(url)
  if (!res.ok) return {status: res.status, ok: false, error: ERRORS_BY_STATUS[res.status] || ERROR_MSG}
  const payload = await res.json()
  return {status: res.status, ok: true, payload}
}

export async function deleteCustomCopilot(copilotId: CustomCopilotId): Promise<APIResult<null>> {
  const res = await verifiedFetchJSON(customCopilotApiPath(copilotId), {method: 'DELETE'})
  if (!res.ok) return res as unknown as FailedAPIResult

  return {status: res.status, ok: true, payload: null}
}

export async function fetchVisibilitySettings(copilotId: CustomCopilotId): Promise<VisibilitySettings> {
  const res = await verifiedFetchJSON(`${customCopilotApiPath(copilotId)}/settings/visibility`)
  if (!res.ok) throw new Error(`Error fetching visibility settings`)
  try {
    const data = await res.json()
    return {
      memberCount: data.member_count && typeof data.member_count === 'number' ? (data.member_count as number) : null,
    }
  } catch (error) {
    throw new Error(`Error parsing visibility settings: ${error}`)
  }
}
