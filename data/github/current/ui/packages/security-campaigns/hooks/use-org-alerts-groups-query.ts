import {useQuery, type UseQueryResult} from '@github-ui/react-query'
import {addGetAlertsGroupsRequestToPath, type GetAlertsGroupsRequest} from '../types/get-alerts-groups-request'
import type {GetAlertsGroupsResponse} from '../types/get-alerts-groups-response'
import {fetchJson} from '../utils/fetch-json'

export function useOrgAlertsGroupsQuery(
  path: string,
  request: GetAlertsGroupsRequest,
): UseQueryResult<GetAlertsGroupsResponse> {
  return useQuery({
    queryKey: ['org-alerts-groups', path, request],
    queryFn: () => {
      return fetchJson(addGetAlertsGroupsRequestToPath(path, request))
    },
  })
}
