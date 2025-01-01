import type {Cursor} from '@github-ui/code-scanning-shared/types/cursor'

export interface GetRuleFindingsRequest {
  cursor: Cursor | null
}

export function addGetRuleFindingsRequestToPath(path: string, request: GetRuleFindingsRequest): string {
  const url = new URL(path, window.location.origin)

  addGetRuleFindingsRequestToParams(url.searchParams, request)

  // Do not include the hostname since we're always on the same domain
  return `${url.pathname}?${url.searchParams.toString()}`
}

export function addGetRuleFindingsRequestToParams(params: URLSearchParams, request: GetRuleFindingsRequest) {
  if (request.cursor) {
    if ('before' in request.cursor) {
      params.set('before', request.cursor.before)
    } else {
      params.set('after', request.cursor.after)
    }
  }
}
