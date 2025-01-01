import {useQuery, type UseQueryResult} from '@github-ui/react-query'
import type {GetAlertsResponse} from '../types/get-alerts-response'
import {fetchJson} from '@github-ui/security-campaigns-shared/utils/fetch-json'
import {addGetAlertsRequestToPath, type GetAlertsRequest} from '../types/get-alerts-request'

export function useRepoAlertsQuery(path: string, request: GetAlertsRequest): UseQueryResult<GetAlertsResponse> {
  return useQuery({
    queryKey: ['repo-alerts', path, request],
    queryFn: () => {
      return fetchJson(addGetAlertsRequestToPath(path, request))
    },
  })
}
