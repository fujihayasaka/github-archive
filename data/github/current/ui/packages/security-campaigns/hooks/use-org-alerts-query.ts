import {useQuery, type UseQueryResult} from '@github-ui/react-query'
import type {GetAlertsResponse} from '../types/get-alerts-response'
import {addGetOrgAlertsRequestToPath, type GetOrgAlertsRequest} from '../types/get-org-alerts-request'
import {fetchJson} from '../utils/fetch-json'

export function useOrgAlertsQuery(
  path: string,
  request: GetOrgAlertsRequest,
  enabled: boolean = true,
): UseQueryResult<GetAlertsResponse> {
  return useQuery({
    queryKey: ['org-alerts', path, request],
    queryFn: () => {
      return fetchJson(addGetOrgAlertsRequestToPath(path, request))
    },
    enabled,
  })
}
