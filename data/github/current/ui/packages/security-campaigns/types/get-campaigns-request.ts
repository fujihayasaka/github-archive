import type {Cursor} from './cursor'
import type {SecurityCampaignState} from './security-campaign-state'

export interface GetCampaignsRequest {
  cursor: Cursor | null
  state: SecurityCampaignState
}

export function addGetCampaignsRequestToPath(path: string, request: GetCampaignsRequest): string {
  const url = new URL(path, window.location.origin)

  if (request.cursor) {
    if ('before' in request.cursor) {
      url.searchParams.set('before', request.cursor.before)
    } else {
      url.searchParams.set('after', request.cursor.after)
    }
  }

  // Do not include the hostname since we're always on the same domain
  return `${url.pathname}?${url.searchParams.toString()}`
}
