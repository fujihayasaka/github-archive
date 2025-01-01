import {
  type FilterKey,
  FilterProviderType,
  type SuppliedFilterProviderOptions,
  TRUE_FALSE_FILTER_VALUES,
} from '../Filter'
import {singleFilterProviderOptions} from '../utils'
import {StaticFilterProvider} from './static'

export class BooleanFilterProvider extends StaticFilterProvider {
  constructor(filter: FilterKey, options?: Omit<SuppliedFilterProviderOptions, 'filterTypes'>) {
    super(filter, TRUE_FALSE_FILTER_VALUES, {...options, ...singleFilterProviderOptions})
    this.type = FilterProviderType.Boolean
  }
}
