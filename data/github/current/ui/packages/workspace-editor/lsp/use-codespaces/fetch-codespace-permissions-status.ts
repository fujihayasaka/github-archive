import {reactFetchJSON} from '@github-ui/verified-fetch'

import {HttpError} from '../../errors'
import {assert} from '../../utilities/asserts'
import {wait} from '../../utilities/wait'
import type {PermissionsStatus} from '../../utilities/workspace-editor-types'

const PERMISSIONS_TIMEOUT_MS = 60_000
const PERMISSIONS_RETRY_INTERVAL_MS = 5_000

/**
 * Fetch the current permissions status for the codespace.
 */
export const fetchCodespacePermissionsStatus = async (url: string): Promise<PermissionsStatus> => {
  const response = await reactFetchJSON(url, {})
  assert(response.ok, HttpError.fromResponse(response, 'Checking codespace permissions failed'))

  const permissionsStatus: PermissionsStatus = await response.json()
  assert('accepted' in permissionsStatus, 'Accepted field missing in permissions check response')

  return permissionsStatus
}

/**
 * Poll until the permissions are accepted.
 */
export const pollForCodespacePermissionsAccepted = async (url: string): Promise<PermissionsStatus | undefined> => {
  const timeout = Date.now() + PERMISSIONS_TIMEOUT_MS

  // Loop until permissions are granted or we time out
  while (Date.now() < timeout) {
    const permissionsStatus = await fetchCodespacePermissionsStatus(url)
    if (permissionsStatus.accepted) {
      return permissionsStatus
    }

    // Wait before checking again
    await wait(PERMISSIONS_RETRY_INTERVAL_MS)
  }
}
