import {useQuery, type UseQueryResult} from '@github-ui/react-query'
import {fetchJson} from '@github-ui/security-campaigns-shared/utils/fetch-json'
import {addGetAlertsGroupsRequestToPath, type GetAlertsGroupsRequest} from '../types/get-alerts-groups-request'
import type {GetAlertsGroupsResponse} from '../types/get-alerts-groups-response'

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
