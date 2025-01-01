import {type FilterConfig, type FilterProviderOptions, type FilterSettings, ProviderSupportStatus} from '../types'
import {NOT_SHOWN} from './filter-constants'

// Exports from the root of the package
export * from './filter-constants'

export const defaultFilterConfig: FilterConfig = {
  filterDelimiter: ':',
  valueDelimiter: ',',
  variant: 'full',
}

export const defaultFilterProviderOptions: FilterProviderOptions = {
  priority: NOT_SHOWN,
  filterTypes: {
    inclusive: true,
    exclusive: true,
    valueless: true,
    multiKey: true,
    multiValue: true,
  },
  support: {
    status: ProviderSupportStatus.Supported,
  },
}

export const defaultFilterSettings: FilterSettings = {
  aliasMatching: false,
  disableAdvancedTextFilter: false,
}

export const MIN_INPUT_WIDTH = 100
