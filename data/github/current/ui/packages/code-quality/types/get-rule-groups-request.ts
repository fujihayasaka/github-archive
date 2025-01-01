import type {Cursor} from '@github-ui/code-scanning-shared/types/cursor'

export interface GetRuleGroupsRequest {
  cursor: Cursor | null
}

export function addGetRuleGroupsRequestToPath(path: string, request: GetRuleGroupsRequest): string {
  const url = new URL(path, window.location.origin)

  addGetRuleGroupsRequestToParams(url.searchParams, request)

  // Do not include the hostname since we're always on the same domain
  return `${url.pathname}?${url.searchParams.toString()}`
}

export function addGetRuleGroupsRequestToParams(params: URLSearchParams, request: GetRuleGroupsRequest) {
  if (request.cursor) {
    if ('before' in request.cursor) {
      params.set('before', request.cursor.before)
    } else {
      params.set('after', request.cursor.after)
    }
  }
}
