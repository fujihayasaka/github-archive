import {Filter, type FilterProps, type SuppliedFilterProvider} from '@github-ui/filter'

import {getCustomPropertiesProvider, type PropertyDefinition} from './providers/custom-properties'
import {getAllDateProviders} from './providers/date'
import {LanguageStaticFilterProvider} from './providers/languages'
import {getAllNumberProviders} from './providers/number'
import {getAllStaticProviders} from './providers/static'

export type {PropertyDefinition}

interface Props extends Omit<FilterProps, 'providers' | 'sx'> {
  definitions: PropertyDefinition[]
}

export function ReposFilter({definitions, ...props}: Props) {
  const actualProviders: SuppliedFilterProvider[] = getDefaultReposProviders(definitions)

  return <Filter {...props} providers={actualProviders} />
}

export function getDefaultReposProviders(definitions: PropertyDefinition[]): SuppliedFilterProvider[] {
  return [
    ...getAllStaticProviders(),
    ...getAllNumberProviders(),
    ...getAllDateProviders(),
    getCustomPropertiesProvider(definitions),
    new LanguageStaticFilterProvider(),
  ]
}
