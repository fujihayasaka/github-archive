import {addGetAlertsRequestToParams, type GetAlertsRequest} from './get-alerts-request'

export type GetOrgAlertsRequest = GetAlertsRequest & {
  repositories?: string[]
}

export function addGetOrgAlertsRequestToPath(path: string, request: GetOrgAlertsRequest): string {
  const url = new URL(path, window.location.origin)

  addGetAlertsRequestToParams(url.searchParams, request)

  if (request.repositories) {
    for (const repository of request.repositories) {
      url.searchParams.append('repository', repository)
    }
  }

  // Do not include the hostname since we're always on the same domain
  return `${url.pathname}?${url.searchParams.toString()}`
}
