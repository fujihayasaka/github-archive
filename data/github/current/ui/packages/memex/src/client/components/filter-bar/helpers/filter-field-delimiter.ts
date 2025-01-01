import {isFeatureEnabled} from '@github-ui/feature-flags'
import type {FilterBlock, FilterConfig, FilterQuery, IndexedBlockValueItem} from '@github-ui/filter'
import type {AsyncFilterProvider, StaticFilterProvider} from '@github-ui/filter/providers'

type Constructor<T> = new (...args: Array<any>) => T

export const fieldDelimiterValidator = (block: FilterBlock, validationResults: Array<IndexedBlockValueItem>) => {
  const hasCommaDelimeterEnabled = isFeatureEnabled('memex_mwl_filter_field_delimiter')
  if (!hasCommaDelimeterEnabled) return validationResults

  const lastIndex = validationResults.length - 1
  const validMemexDelimiter = block.raw.trim().endsWith(',')
  const lastResult = validationResults?.[lastIndex]
  const lastFieldResult = validationResults[lastIndex]?.valid || validMemexDelimiter

  if (lastFieldResult && !validationResults[lastIndex]?.value) {
    return [
      ...validationResults.slice(0, lastIndex),
      {
        ...lastResult,
        validations: undefined,
        valid: true,
        // Ensure the following fields are defined with the correct types
        value: lastResult?.value ?? '',
        startIndex: lastResult?.startIndex ?? 0,
        endIndex: lastResult?.endIndex ?? validationResults[lastIndex]?.startIndex ?? 0,
        hasCaret: lastResult?.hasCaret ?? false,
      },
    ]
  }

  return validationResults
}

/**
 * This mixin is used to ensure that the last field in a filter block is always valid based on the base class validation
 * or the comma-delimited value of the last field. It extends the AsyncFilterProvider class and overrides the validateFilterBlockValues method.
 *
 * @template TBase The type of the base class
 * @returns A new class that extends the base class and overrides the validateFilterBlockValues method
 */
export function MemexAsyncFilterDelimiter<TBase extends Constructor<AsyncFilterProvider<any>>>(Base: TBase) {
  return class extends Base {
    override async validateFilterBlockValues(
      filterQuery: FilterQuery,
      block: FilterBlock,
      values: Array<IndexedBlockValueItem>,
    ): Promise<Array<IndexedBlockValueItem>> {
      const results = await super.validateFilterBlockValues(filterQuery, block, values)
      return fieldDelimiterValidator(block, results)
    }
  }
}

/**
 * This mixin is used to ensure that the last field in a filter block is always valid based on the base class validation
 * or the comma-delimited value of the last field. It extends the StaticFilterProvider class and overrides the validateFilterBlockValues method.
 *
 * @template TBase The type of the base class
 * @returns A new class that extends the base class and overrides the validateFilterBlockValues method
 */
export function MemexStaticFilterDelimiter<TBase extends Constructor<StaticFilterProvider>>(Base: TBase) {
  return class extends Base {
    override async validateFilterBlockValues(
      filterQuery: FilterQuery,
      block: FilterBlock,
      values: Array<IndexedBlockValueItem>,
      config: FilterConfig,
    ): Promise<Array<IndexedBlockValueItem>> {
      const results = await super.validateFilterBlockValues(filterQuery, block, values, config)
      return fieldDelimiterValidator(block, results)
    }
  }
}
