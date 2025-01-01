import {keepPreviousData, useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {repoModelsPath} from '@github-ui/paths'
import type {ModelRepoPromptsRoutePayload} from '../types'

/**
 * Fetches a particular page of prompts from the specified repository.
 *
 * @param owner - The owner of the repository.
 * @param repo - The name of the repository.
 * @param page - The page number to fetch. If zero, the query will not be executed.
 */
export function usePromptsQuery(owner: string, repo: string, page: number) {
  return useQuery<ModelRepoPromptsRoutePayload>({
    queryKey: ['github-models', 'prompts', owner, repo, page],
    async queryFn() {
      const url = `${repoModelsPath({repo: {ownerLogin: owner, name: repo}, action: 'prompts'})}?page=${page}`
      const res = await verifiedFetchJSON(url)
      if (!res.ok) throw new Error(await res.text())
      const result = (await res.json()) as {payload: ModelRepoPromptsRoutePayload}
      return result.payload
    },
    enabled: owner !== '' && repo !== '' && page > 0,
    placeholderData: keepPreviousData,
  })
}
