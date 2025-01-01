import type {Model} from '@github-ui/marketplace-common'
import {useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

/**
 * Fetches a list of available models
 *
 * Eventually we'll want to make this dependent on the current user and repo context, but for now
 * we just call the marketplace API
 */
export function useModelsQuery() {
  return useQuery<Model[]>({
    queryKey: ['github-models', 'models'],
    initialData: [],
    async queryFn() {
      const res = await verifiedFetchJSON('/marketplace/models')
      if (!res.ok) throw new Error(await res.text())
      return res.json()
    },
  })
}
