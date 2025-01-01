import type {AlertsCursor} from './alerts-cursor'

export interface GetAlertsRequest {
  query: string
  cursor: AlertsCursor | null
}

export function addGetAlertsRequestToPath(path: string, request: GetAlertsRequest): string {
  const url = new URL(path, window.location.origin)

  url.searchParams.set('query', request.query ?? '')

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
