import {useQuery, type UseQueryResult} from '@github-ui/react-query'
import {fetchJson} from '../utils/fetch-json'
import type {User} from '../types/user'
import type {Team} from '../types/team'

export type SecurityManagersResult = {
  managers: User[]
  teamManagers: Team[] | null
}

export function useCampaignManagersQuery(path: string, enabled: boolean): UseQueryResult<SecurityManagersResult> {
  return useQuery({
    queryKey: ['campaign-managers', path],
    queryFn: () => {
      return fetchJson(path)
    },
    enabled,
  })
}
