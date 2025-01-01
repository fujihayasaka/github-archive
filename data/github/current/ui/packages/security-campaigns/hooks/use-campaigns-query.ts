import {useQuery, type UseQueryResult} from '@github-ui/react-query'
import {addGetCampaignsRequestToPath, type GetCampaignsRequest} from '../types/get-campaigns-request'
import type {GetCampaignsResponse} from '../types/get-campaigns-response'
import {
  securityCampaignOrgClosedListPath,
  securityCampaignOrgOpenListPath,
  securityCampaignOrgDraftListPath,
} from '@github-ui/paths'
import {assertNever} from '../utils/assert-never'
import {fetchJson} from '../utils/fetch-json'

export function useCampaignsQuery(
  organizationLogin: string,
  request: GetCampaignsRequest,
): UseQueryResult<GetCampaignsResponse> {
  let path: string

  switch (request.state) {
    case 'open':
      path = securityCampaignOrgOpenListPath({org: organizationLogin})
      break
    case 'closed':
      path = securityCampaignOrgClosedListPath({org: organizationLogin})
      break
    case 'draft':
      path = securityCampaignOrgDraftListPath({org: organizationLogin})
      break
    default:
      assertNever(request.state)
  }

  return useQuery({
    queryKey: ['campaigns-list', path, request],
    queryFn: () => {
      return fetchJson(addGetCampaignsRequestToPath(path, request))
    },
  })
}
