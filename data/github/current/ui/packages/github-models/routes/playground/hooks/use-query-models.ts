import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useQuery} from '@github-ui/react-query'
import type {Model} from '@github-ui/marketplace-common'

export function useLowRateLimitTierModels(
  publisher: string,
  onComparisonMode: boolean,
  rate_limit_tier: string | null,
) {
  return useQuery<Model[]>({
    queryKey: ['github-models', 'models', 'low', publisher],
    initialData: [],
    async queryFn() {
      const params = new URLSearchParams()
      params.append('publisher', publisher)
      params.append('rate_limit_tier', 'low')
      const path = `/marketplace/models?${params.toString()}`
      const res = await verifiedFetchJSON(path)
      if (!res.ok) throw new Error(await res.text())
      return res.json()
    },
    enabled: !onComparisonMode && rate_limit_tier !== null && rate_limit_tier !== 'low',
  })
}

export function useAvailableModels() {
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
