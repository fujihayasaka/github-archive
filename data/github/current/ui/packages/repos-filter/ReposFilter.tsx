import {Filter, type FilterProps, type FilterProvider} from '@github-ui/filter'

import {
  getCustomPropertiesProviders,
  type PropertyDefinition,
  type ReposCustomPropertiesProviderKey,
} from './providers/custom-properties'
import {getAllDateProviders, type ReposDateProviderKey} from './providers/date'
import {LanguageStaticFilterProvider, type ReposLanguageProviderKey} from './providers/languages'
import {getAllNumberProviders, type ReposNumberProviderKey} from './providers/number'
import {getAllStaticProviders, type ReposStaticProviderKey} from './providers/static'

export type {PropertyDefinition}

type ReposProviderKey =
  | ReposStaticProviderKey
  | ReposNumberProviderKey
  | ReposDateProviderKey
  | ReposCustomPropertiesProviderKey
  | ReposLanguageProviderKey
interface Props extends Omit<FilterProps, 'providers' | 'sx'> {
  definitions: PropertyDefinition[]
  /**
   * Filter provider keys with a special case for custom properties - `custom-properties`.
   * If defined, restricts filter providers to the set specified in this property.
   * If undefined, includes all filter providers.
   */
  allowedProviders?: ReposProviderKey[]
}

export function ReposFilter({definitions, allowedProviders, ...props}: Props) {
  const providers: FilterProvider[] = getProviders(definitions, allowedProviders)

  return <Filter {...props} providers={providers} />
}

function getProviders(
  definitions: PropertyDefinition[],
  allowedProviders: ReposProviderKey[] | undefined,
): FilterProvider[] {
  const allProviders = [
    ...getAllStaticProviders(),
    ...getAllNumberProviders(),
    ...getAllDateProviders(),
    ...getCustomPropertiesProviders(definitions),
    new LanguageStaticFilterProvider(),
  ]

  if (!allowedProviders) {
    return allProviders
  }

  const providerKeySet = new Set<string>(allowedProviders)
  const predicate = ({key}: FilterProvider) => {
    if (providerKeySet.has('custom-properties') && key.startsWith('props.')) {
      return true
    }

    return providerKeySet.has(key)
  }

  return allProviders.filter(predicate)
}
