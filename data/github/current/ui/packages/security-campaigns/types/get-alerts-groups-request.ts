import type {Cursor} from '@github-ui/code-scanning-shared/types/cursor'

export type AlertsGroup = 'repository' | 'none'
const defaultAlertsGroup: AlertsGroup = 'repository'

export function parseAlertsGroup(v: string | null, defaultGroup = defaultAlertsGroup): AlertsGroup {
  if (v === 'repository') {
    return 'repository'
  }
  if (v === 'none') {
    return 'none'
  }
  return defaultGroup
}

export interface GetAlertsGroupsRequest {
  query: string
  group: AlertsGroup
  cursor: Cursor | null
}

export function addGetAlertsGroupsRequestToPath(path: string, request: GetAlertsGroupsRequest): string {
  const url = new URL(path, window.location.origin)

  url.searchParams.set('query', request.query ?? '')
  url.searchParams.set('group', request.group)

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
