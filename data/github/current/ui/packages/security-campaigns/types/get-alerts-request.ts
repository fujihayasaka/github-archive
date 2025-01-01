import type {Cursor} from '@github-ui/code-scanning-shared/types/cursor'

export interface GetAlertsRequest {
  query: string
  cursor: Cursor | null
}

export function addGetAlertsRequestToPath(path: string, request: GetAlertsRequest): string {
  const url = new URL(path, window.location.origin)

  addGetAlertsRequestToParams(url.searchParams, request)

  // Do not include the hostname since we're always on the same domain
  return `${url.pathname}?${url.searchParams.toString()}`
}

export function addGetAlertsRequestToParams(params: URLSearchParams, request: GetAlertsRequest) {
  params.set('query', request.query ?? '')

  if (request.cursor) {
    if ('before' in request.cursor) {
      params.set('before', request.cursor.before)
    } else {
      params.set('after', request.cursor.after)
    }
  }
}
