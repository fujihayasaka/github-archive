import {useQuery, type UseQueryResult} from '@github-ui/react-query'
import {fetchJson} from '@github-ui/security-campaigns-shared/utils/fetch-json'
import {addGetClosedCampaignsRequestToPath, type GetClosedCampaignsRequest} from '../types/get-closed-campaigns-request'
import type {GetClosedCampaignsResponse} from '../types/get-closed-campaigns-response'

export function useClosedCampaignsQuery(
  path: string,
  request: GetClosedCampaignsRequest,
): UseQueryResult<GetClosedCampaignsResponse> {
  return useQuery({
    queryKey: ['closed-campaigns', path, request],
    queryFn: () => {
      return fetchJson(addGetClosedCampaignsRequestToPath(path, request))
    },
  })
}
