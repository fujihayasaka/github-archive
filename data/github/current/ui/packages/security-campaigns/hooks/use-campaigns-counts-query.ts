import {securityCampaignOrgCampaignsCountsPath} from '@github-ui/paths'
import {useQuery, type UseQueryResult} from '@github-ui/react-query'
import type {SecurityCampaignCounts} from '../types/security-campaign-counts'
import {fetchJson} from '../utils/fetch-json'

export function useCampaignsCountsQuery(
  organizationLogin: string,
  initialData: SecurityCampaignCounts,
): UseQueryResult<SecurityCampaignCounts> {
  const path = securityCampaignOrgCampaignsCountsPath({org: organizationLogin})

  return useQuery({
    queryKey: ['campaigns-counts', path],
    queryFn: () => {
      return fetchJson(path)
    },
    initialData,
    staleTime: 1000,
  })
}
