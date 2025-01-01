import {useQuery, type UseQueryResult} from '@github-ui/react-query'
import type {GetAlertsResponse} from '../types/get-alerts-response'
import {addGetAlertsRequestToPath, type GetAlertsRequest} from '../types/get-alerts-request'
import {fetchJson} from '../utils/fetch-json'

export function useRepoAlertsQuery(path: string, request: GetAlertsRequest): UseQueryResult<GetAlertsResponse> {
  return useQuery({
    queryKey: ['repo-alerts', path, request],
    queryFn: () => {
      return fetchJson(addGetAlertsRequestToPath(path, request))
    },
  })
}
