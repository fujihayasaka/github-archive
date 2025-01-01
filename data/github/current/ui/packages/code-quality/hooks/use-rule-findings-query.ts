import {useQuery, type UseQueryResult} from '@github-ui/react-query'
import type {GetRuleFindingsResponse} from '../types/get-rule-findings-response'
import {fetchJson} from '../utils/fetch-json'
import {addGetRuleFindingsRequestToPath, type GetRuleFindingsRequest} from '../types/get-rule-findings-request'

export function useRuleFindingsQuery(
  path: string,
  request: GetRuleFindingsRequest,
): UseQueryResult<GetRuleFindingsResponse> {
  return useQuery({
    queryKey: ['rule-findings', path, request],
    queryFn: () => {
      return fetchJson(addGetRuleFindingsRequestToPath(path, request))
    },
  })
}
