import {useQuery, type UseQueryResult} from '@github-ui/react-query'
import {fetchJson} from '../utils/fetch-json'
import type {GetRuleFilesResponse} from '../types/get-rule-files-response'

export function useRuleFilesQuery(path: string): UseQueryResult<GetRuleFilesResponse> {
  return useQuery({
    queryKey: ['rule-files', path],
    queryFn: () => {
      return fetchJson(path)
    },
  })
}
