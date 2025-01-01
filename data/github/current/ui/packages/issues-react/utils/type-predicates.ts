import type {FilterProvider} from '@github-ui/filter'
import type {TypeFilterProvider} from '@github-ui/filter/providers/type'

export function isTypeFilterProvider(filterProvider: FilterProvider): filterProvider is TypeFilterProvider {
  return (filterProvider as TypeFilterProvider).displayName === 'Type'
}
