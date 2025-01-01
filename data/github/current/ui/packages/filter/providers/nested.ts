import {CheckCircleIcon, type Icon, SingleSelectIcon, TypographyIcon} from '@primer/octicons-react'

import {defaultFilterProviderOptions, NOT_SHOWN} from '../Filter'
import type {FilterKey, FilterProvider, FilterSuggestion, OptionalKey, SuppliedFilterProviderOptions} from '../types'
import {FilterProviderType} from '../types'
import {BooleanFilterProvider} from './boolean'
import {KeyOnlyFilterProvider} from './key-only'
import {StaticFilterProvider} from './static'

type BaseSubFilterKey = OptionalKey<Omit<FilterKey, 'priority'>, 'icon'> & {
  type: FilterProviderType
  icon?: Icon
}

type SelectSubFilterKey = BaseSubFilterKey & {
  type: 'select'
  values: FilterSuggestion[]
}

type FixedSubFilterKey = BaseSubFilterKey & {
  type: 'boolean' | 'text'
}

type MultiLevelKey = {
  subKeys: Array<SelectSubFilterKey | FixedSubFilterKey>
} & FilterKey

const subKeyIcons = {
  boolean: CheckCircleIcon,
  select: SingleSelectIcon,
  text: TypographyIcon,
}

export class NestedFilterProvider {
  subKeys: BaseSubFilterKey[]
  filterProviders: FilterProvider[]

  constructor(filterKey: MultiLevelKey, options?: SuppliedFilterProviderOptions) {
    const {subKeys, ...rest} = filterKey
    this.subKeys = subKeys

    this.filterProviders = subKeys.map(subKey => {
      const subKeyObject = {
        ...subKey,
        type: subKey.type,
        key: `${rest.key}.${subKey.key}`,
        displayName: subKey.displayName ?? subKey.key,
        description: subKey.description,
        priority: NOT_SHOWN,
        icon: subKey.icon ?? subKeyIcons[subKey.type],
      }

      if (subKey.type === FilterProviderType.Boolean) {
        return new BooleanFilterProvider(subKeyObject, options)
      } else if (subKey.type === FilterProviderType.Select) {
        const selectFilterProvider = new StaticFilterProvider(subKeyObject, subKey.values, {
          ...subKey.options,
          filterTypes: {
            ...defaultFilterProviderOptions.filterTypes,
            ...subKey.options?.filterTypes,
          },
        })
        selectFilterProvider.type = subKeyObject.type
        return selectFilterProvider
      } else {
        return new KeyOnlyFilterProvider(subKeyObject, subKey.options)
      }
    })

    this.filterProviders.push(new StaticFilterProvider({...rest, key: `${rest.key}.`}, [], options))
  }
}
