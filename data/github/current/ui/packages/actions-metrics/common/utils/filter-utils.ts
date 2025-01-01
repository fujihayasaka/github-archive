import {FilterOperator, FilterProviderType, type FilterBlock, type FilterProvider} from '@github-ui/filter'
import {OperatorType} from '../models/enums'
import type {FilterValue} from '../models/models'
import {Services} from '../services/services'
import type {IFilterService} from '../services/filter-service'
import {Utils} from './utils'
import {getUnescapedFilterValue} from '@github-ui/filter/utils'
import type {IErrorService} from '../services/error-service'
import {FilterQueryParser} from '@github-ui/filter/parser'
import {COLUMNS} from '../constants/constants'
import type {AnyUsageItem} from '../../views/usage/models/models'
import type {AnyPerformanceItem} from '../../views/performance/models/models'

export class FilterUtils {
  public static parseFilter = (providers: FilterProvider[], filter?: string): FilterValue[] | undefined => {
    if (!filter?.trim()) {
      return undefined
    }

    const providersMap = new Map<string, FilterProvider>()
    for (const provider of providers) {
      providersMap.set(provider.key, provider)
    }

    const filterQueryParser = new FilterQueryParser(providers)
    const parsedQuery = filterQueryParser.parse(filter)

    let filterBlocks = parsedQuery.blocks.filter(b => b.type === 'text' || b.type === 'filter')

    if (!FilterUtils.TextFilterSupportEnabled(providers)) {
      filterBlocks = filterBlocks.filter(b => b.type === 'filter')
    }

    const filterValues: FilterValue[] = []
    const foundKeys = new Set<string>()

    for (let i = 0; i < filterBlocks.length; i++) {
      try {
        if (filterBlocks[i]?.type === 'text') {
          const block = filterBlocks[i]!
          const value = block?.raw ?? ''
          const textValue = getUnescapedFilterValue(value) ?? ''
          if (textValue) {
            const filterValue: FilterValue = {
              key: 'text',
              values: [textValue],
              order: i,
              operator: OperatorType.Contains,
              display: block.raw,
            }

            filterValues.push(filterValue)
          }
        } else {
          const block = filterBlocks[i] as FilterBlock
          const key = block.key.value
          const realFilterKey = key?.startsWith('-') && key?.length > 1 ? key.substring(1, key.length) : key ?? ''

          if (key && key !== '-' && block.value.values.length && !foundKeys.has(realFilterKey)) {
            // regular filter
            const provider = providersMap.get(realFilterKey)!
            const values = FilterUtils.getFilterValues(block, provider)
            if (values.length) {
              const filterValue: FilterValue = {
                key: realFilterKey,
                values,
                order: i,
                display: block.raw,
                operator: getOperatorForSpecialColumns(realFilterKey, FilterUtils.getOperator(block)),
              }

              if (filterValue.operator !== OperatorType.Unknown && filterValue.values.length) {
                foundKeys.add(realFilterKey)
                filterValues.push(filterValue)
              }
            }
          }
        }
      } catch (e) {
        const errorService = Services.get<IErrorService>('IErrorService')
        errorService.log(e as Error)
      }
    }

    const sorted = filterValues.sort((a, b) => {
      let result = a.key.localeCompare(b.key)
      // if keys are the same, sort by order
      if (result === 0) {
        result = a.order - b.order
      }
      return result
    })
    return sorted.length > 0 ? sorted : undefined
  }

  public static stringifyFilters = (filters?: FilterValue[]): string | undefined => {
    if (!filters?.length) {
      return undefined
    }

    return filters
      .sort((a, b) => a.order - b.order)
      .map(filter => this.stringifyFilter(filter))
      .join(' ')
  }

  public static stringifyFilter = (filter: FilterValue): string => {
    if (filter.display) {
      return filter.display
    }

    // only converting from equals operator is needed right now, since others should have display as this is mainly used
    // when setting filters for custom linking between tabs (e.g clicking # of jobs on WF tab takes you to jobs tab with
    // some filters set)
    if (filter.operator === OperatorType.Equals) {
      return `${filter.key}:${filter.values.join(',')}`
    }

    return ''
  }

  private static getFilterValues = (block: FilterBlock, provider: FilterProvider): string[] => {
    if (provider.type === FilterProviderType.Number) {
      const operator = FilterUtils.getOperator(block)
      const value = block.value.values[0]?.value as string
      if (operator !== OperatorType.Unknown && value?.length) {
        if (operator === OperatorType.GreaterEqualTo || operator === OperatorType.LessEqualTo) {
          return [value.substring(2)]
        }
        if (operator === OperatorType.GreaterThan || operator === OperatorType.LessThan) {
          return [value.substring(1)]
        }
      }
    }

    const filterService = Services.get<IFilterService>('IFilterService')

    const values = block.value.values.map(b => getUnescapedFilterValue(b.value as string)).filter(s => !!s) as string[]

    return Utils.getUniqueSortedNonEmpty(values.filter(v => filterService.isFilterValueValid(v, provider)))
  }

  public static getOperator = (block: FilterBlock): OperatorType => {
    switch (block.operator) {
      case FilterOperator.IsOneOf:
        return OperatorType.Equals
      case FilterOperator.IsNotOneOf:
        return OperatorType.NotEquals
      case FilterOperator.GreaterThanOrEqualTo:
        return OperatorType.GreaterEqualTo
      case FilterOperator.GreaterThan:
        return OperatorType.GreaterThan
      case FilterOperator.LessThanOrEqualTo:
        return OperatorType.LessEqualTo
      case FilterOperator.LessThan:
        return OperatorType.LessThan
      case FilterOperator.Between:
        return OperatorType.Between
      case FilterOperator.EqualTo:
        return OperatorType.Equals
      default:
        return OperatorType.Unknown
    }
  }

  public static isAsync = (provider: FilterProvider): boolean => {
    return !provider.filterValues?.length
  }

  public static TextFilterSupportEnabled = (providers: FilterProvider[]): boolean => {
    // ignore text blocks if there are no async filters, because we only support free text search on async providers
    return providers.find(p => FilterUtils.isAsync(p) && p.key.indexOf(COLUMNS.repository) === -1) !== undefined
  }

  public static getFilterForCrossLink(
    snakeCaseKey: string,
    item: AnyUsageItem | AnyPerformanceItem,
  ): FilterValue | undefined {
    if (snakeCaseKey === COLUMNS.repository && item.repository) {
      return FilterUtils.getFilterValue(COLUMNS.repository, [item.repository.name])
    }

    if (
      (snakeCaseKey === COLUMNS.workflowFileName || snakeCaseKey === COLUMNS.workflowFilePath) &&
      item.workflowFilePath
    ) {
      return FilterUtils.getFilterValue(COLUMNS.workflowFileName, [Utils.getFileNameFromPath(item.workflowFilePath)!])
    }

    const value = (item as object)[Utils.snakeToCamel(snakeCaseKey) as keyof object] as string | undefined
    if (value) {
      return FilterUtils.getFilterValue(snakeCaseKey, [value])
    }

    return undefined
  }

  public static getFilterValue(key: string, values: string[], operator = OperatorType.Equals): FilterValue | undefined {
    return {
      key,
      operator: getOperatorForSpecialColumns(key, operator),
      order: 0,
      values: values.map(v => (v.includes(' ') || v.includes(':') ? `"${v}"` : v)),
    }
  }
}

const getOperatorForSpecialColumns = (key: string, operator: OperatorType) => {
  if (key === COLUMNS.runnerLabels) {
    if (operator === OperatorType.Equals) {
      return OperatorType.ListContains
    } else {
      return OperatorType.NotListContains
    }
  }

  return operator
}
