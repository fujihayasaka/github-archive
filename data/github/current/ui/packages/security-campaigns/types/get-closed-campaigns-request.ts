import type {Cursor} from './cursor'

export interface GetClosedCampaignsRequest {
  cursor: Cursor | null
}

export function addGetClosedCampaignsRequestToPath(path: string, request: GetClosedCampaignsRequest): string {
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
