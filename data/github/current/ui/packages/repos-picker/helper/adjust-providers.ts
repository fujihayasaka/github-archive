import type {SuppliedFilterProvider} from '@github-ui/filter'
import {NestedFilterProvider} from '@github-ui/filter/providers'

import type {PickerScope} from '../types'

export function adjustProvidersToScope(
  providers: SuppliedFilterProvider[],
  scope: PickerScope,
): SuppliedFilterProvider[] {
  if (scope.visibility) {
    return updateVisibilityProvider(providers, scope.visibility)
  }

  return providers
}

function updateVisibilityProvider(providers: SuppliedFilterProvider[], visibility: string[]): SuppliedFilterProvider[] {
  const isSingleVisibilityValue = visibility.length === 1

  return providers.filter(provider => {
    if (provider instanceof NestedFilterProvider || provider.key !== 'visibility') {
      return true
    }

    if (isSingleVisibilityValue) return false

    provider.filterValues = (provider.filterValues || []).filter(
      ({value}) => typeof value === 'string' && visibility.includes(value),
    )

    return true
  })
}
