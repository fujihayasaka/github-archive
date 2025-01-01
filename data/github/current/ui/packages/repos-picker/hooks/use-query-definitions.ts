import {OrgFilterProvider} from '@github-ui/filter/providers'
import {useQuery} from '@github-ui/react-query'
import {getDefaultReposProviders} from '@github-ui/repos-filter/providers'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import {adjustProvidersToScope} from '../helper/adjust-providers'
import {reposPickerDefinitionsPath} from '../paths'
import type {PickerScope, PropertyDefinition} from '../types'

const DEFINITIONS_STALE_TIME_IN_MS = 1000 * 60 * 5 // 5 minutes

export function useDefaultReposProviders(scope: PickerScope) {
  const {data: definitions} = useQueryDefinitions({scope})
  const providers = getDefaultReposProviders(definitions || [])
  if (scope && scope.type === 'enterprise') {
    providers.push(
      new OrgFilterProvider({
        businessSlug: scope.slug,
        filterTypes: {valueless: false, multiKey: true, multiValue: false},
      }),
    )
  }

  return adjustProvidersToScope(providers, scope)
}

export function useQueryDefinitions({scope, enabled = true}: {scope: PickerScope; enabled?: boolean}) {
  const isBizOrOrg = scope.type === 'enterprise' || scope.type === 'organization'

  return useQuery<PropertyDefinition[]>({
    queryKey: ['repos-picker', 'definitions', scope],
    enabled: isBizOrOrg && enabled,
    queryFn: async () => {
      const fetchDefinitionsUrl = reposPickerDefinitionsPath(scope)

      const response = await verifiedFetchJSON(fetchDefinitionsUrl)
      if (!response.ok) return []

      const responseData = await response.json()
      return responseData.definitions
    },
    staleTime: DEFINITIONS_STALE_TIME_IN_MS,
  })
}
