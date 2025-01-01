import {useMutation} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {RepositoryAccessPolicy, UpdateRepositoryAccessPolicyPayload} from '../types'
import {repositorySettingsModelsAccessPolicyPath} from '@github-ui/paths'

export function useUpdateRepoAccessPolicy(ownerDisplayLogin: string, repositoryName: string) {
  const path = repositorySettingsModelsAccessPolicyPath({owner: ownerDisplayLogin, repo: repositoryName})
  return useMutation({
    mutationKey: ['set-github-models-repository-access-policy', ownerDisplayLogin, repositoryName],
    mutationFn: async ({method}: UpdateRepositoryAccessPolicyPayload) => {
      const result = await verifiedFetchJSON(path, {method})
      if (result.ok) {
        const json = await result.json()
        return json as RepositoryAccessPolicy
      }
      throw new Error(`${result.status} on ${result.url}, unexpected status or payload`)
    },
  })
}

/**
 * Returns the request configuration to turn off the repository configuration setting for GitHub Models.
 */
export function disableRepoModelsPayload(): UpdateRepositoryAccessPolicyPayload {
  return {method: 'DELETE'}
}

/**
 * Returns the request configuration to turn on the repository configuration setting for GitHub Models.
 */
export function enableRepoModelsPayload(): UpdateRepositoryAccessPolicyPayload {
  return {method: 'POST'}
}
