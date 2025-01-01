import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useQuery} from '@github-ui/react-query'
import type {ModelDetails} from '../../../types'

export function useModelDetailsQuery(modelRegistry: string, modelName: string) {
  return useQuery<ModelDetails>({
    queryKey: ['github-models', 'models', modelRegistry, modelName],
    enabled: !!modelName && !!modelRegistry,
    async queryFn() {
      if (modelName === undefined || modelRegistry === undefined) return
      const res = await verifiedFetchJSON(`/marketplace/models/${modelRegistry}/${modelName}/details`)
      if (!res.ok) throw new Error(await res.text())
      return res.json()
    },
  })
}
