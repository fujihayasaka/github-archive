import {type FilterKey, FilterProviderType, TRUE_FALSE_FILTER_VALUES} from '../Filter'
import {singleFilterProviderOption} from '../utils'
import {StaticFilterProvider} from './static'

export class BooleanFilterProvider extends StaticFilterProvider {
  constructor(filter: FilterKey) {
    super(filter, TRUE_FALSE_FILTER_VALUES, singleFilterProviderOption)
    this.type = FilterProviderType.Boolean
  }
}
