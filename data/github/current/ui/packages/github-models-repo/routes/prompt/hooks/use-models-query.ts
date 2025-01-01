import {useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {repoModelsPath} from '@github-ui/paths'
import type {RepoModel} from '../../../types'

/**
 * Fetches a list of available models.
 *
 * @param owner - The owner of the repository.
 * @param repo - The name of the repository.
 */
export function useModelsQuery(owner: string, repo: string) {
  return useQuery<RepoModel[]>({
    queryKey: ['github-models', 'models', owner, repo],
    initialData: [],
    async queryFn() {
      const res = await verifiedFetchJSON(repoModelsPath({repo: {ownerLogin: owner, name: repo}}))
      if (!res.ok) throw new Error(await res.text())
      return res.json()
    },
    enabled: owner !== '' && repo !== '',
  })
}
