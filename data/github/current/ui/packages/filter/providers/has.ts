import {type FilterSuggestion, FilterValueType, type SuppliedFilterProviderOptions} from '../types'
import {ValuePresenceFilterProvider} from './value-presence'

export class HasFilterProvider extends ValuePresenceFilterProvider {
  constructor(filterValues: FilterSuggestion[], options?: SuppliedFilterProviderOptions) {
    super(filterValues, FilterValueType.HasValue, options)
  }
}
