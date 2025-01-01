import {codeScanningAvailableAssigneesPath} from '@github-ui/paths'
import {useQuery, type UseQueryOptions, type UseQueryResult} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {Assignee} from '../types'

export type AvailableAssigneesRequest = {
  owner: string
  repo: string
  query?: string
}

export type AvailableAssigneesResponse = {
  users: Assignee[]
}

export function useAvailableAssigneesQuery(
  request: AvailableAssigneesRequest,
  options?: Omit<UseQueryOptions<AvailableAssigneesRequest, Error, AvailableAssigneesResponse>, 'queryKey' | 'queryFn'>,
): UseQueryResult<AvailableAssigneesResponse> {
  return useQuery({
    queryKey: ['code-scanning-assignees-section', request],
    queryFn: async () => {
      const {owner, repo, query = ''} = request

      const path = codeScanningAvailableAssigneesPath({
        owner,
        repo,
      })
      const url = new URL(path, window.location.origin)
      url.searchParams.set('query', query)
      const response = await verifiedFetchJSON(`${url.pathname}${url.search}`)
      if (!response.ok) {
        throw new Error(`${response.status} on ${response.url}`)
      }
      return response.json()
    },
    ...options,
  })
}
