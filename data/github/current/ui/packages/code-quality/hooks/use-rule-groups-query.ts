import {useQuery, type UseQueryResult} from '@github-ui/react-query'
import {fetchJson} from '../utils/fetch-json'
import type {GetRuleGroupsResponse} from '../types/get-rule-groups-response'
import {addGetRuleGroupsRequestToPath, type GetRuleGroupsRequest} from '../types/get-rule-groups-request'

export function useRuleGroupsQuery(path: string, request: GetRuleGroupsRequest): UseQueryResult<GetRuleGroupsResponse> {
  return useQuery({
    queryKey: ['rule-groups', path, request],
    queryFn: () => {
      return fetchJson(addGetRuleGroupsRequestToPath(path, request))
    },
  })
}
