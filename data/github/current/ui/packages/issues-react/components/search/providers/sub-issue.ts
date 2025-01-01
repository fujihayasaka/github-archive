import {
  FilterProviderType,
  defaultFilterProviderOptions,
  type FilterQuery,
  ValidationTypes,
  type FilterBlock,
  type IndexedBlockValueItem,
  type ARIAFilterSuggestion,
  type AnyBlock,
  type FilterConfig,
  type MutableFilterBlock,
} from '@github-ui/filter'
import {Strings} from '@github-ui/filter/constants/strings'
import {StaticFilterProvider} from '@github-ui/filter/providers'
import {
  getExcludeKeySuggestion,
  getFilterValue,
  getHasValueSuggestion,
  getLastFilterBlockValue,
  getNoValueSuggestion,
  isEmptyFilterBlockValue,
  isFilterBlock,
  sanitizeOperators,
} from '@github-ui/filter/utils'
import {IssueTracksIcon} from '@primer/octicons-react'

// NOTE: In the future, this will not be a static filter provider, as we will
// want to add asynchronously-fetched suggestions from the server to get the available
// sub-issues.
export class SubIssueFilterProvider extends StaticFilterProvider {
  private hasFilterEnabled: boolean

  constructor(hasFilterEnabled: boolean = false) {
    const filterKey = {
      key: 'sub-issue',
      displayName: 'Sub-issue',
      icon: IssueTracksIcon,
      priority: 5,
      type: FilterProviderType.Text,
    }

    super(filterKey, [], {
      // We are overriding the given `filterTypes` back to the defaults
      filterTypes: {...defaultFilterProviderOptions?.filterTypes, hasValue: hasFilterEnabled},
    })

    this.hasFilterEnabled = hasFilterEnabled
  }

  override getSuggestions(
    _filterQuery: FilterQuery,
    filterBlock: AnyBlock | MutableFilterBlock,
    _config: FilterConfig,
    caretIndex?: number | null,
  ): ARIAFilterSuggestion[] | null {
    const lastValue = getLastFilterBlockValue(filterBlock, caretIndex)
    const filterProviderKey = (filterBlock as FilterBlock).provider.key
    const suggestions: ARIAFilterSuggestion[] = []

    if (isEmptyFilterBlockValue(filterBlock) && filterBlock.raw !== `-${filterProviderKey}:`) {
      suggestions.push(getNoValueSuggestion(this.displayName, this.icon))

      if (this.hasFilterEnabled) {
        suggestions.push(getHasValueSuggestion(this.displayName, this.icon))
      }
    }

    if (lastValue === '' && isFilterBlock(filterBlock) && filterBlock.raw !== `-${filterProviderKey}:`) {
      const excludeKeySuggestion = getExcludeKeySuggestion(filterProviderKey)
      suggestions.unshift(excludeKeySuggestion)
    }

    return suggestions
  }

  override validateFilterBlockValues(
    _filterQuery: FilterQuery,
    _block: FilterBlock,
    values: IndexedBlockValueItem[],
  ): Promise<IndexedBlockValueItem[]> {
    // Matches the nwo#number format e.g. "github/github#123"
    const nwoRegex = new RegExp(
      '^"?' + // Optional quote at start of value
        '(?<owner>[a-zA-Z0-9-_.]+)' + // Owner string
        '/' + // Slash between owner and repo
        '(?<repo>[a-zA-Z0-9-_.]+)' + // Repo string
        '#' + // Hash between repo and number
        '(?<number>[0-9]+)' + // Number
        '"?$', // Optional quote at end of value
    )
    const validations = values.map(value => {
      const filterValue = sanitizeOperators(getFilterValue(value.value))
      if (values.length < 1 || !filterValue) {
        return {
          ...value,
          valid: false,
          validations: [
            {
              type: ValidationTypes.EmptyValue,
              message: Strings.filterValueEmpty(this.key),
            },
          ],
        }
      }
      if (!nwoRegex.test(filterValue)) {
        return {
          ...value,
          valid: false,
          validations: [
            {
              type: ValidationTypes.InvalidValue,
              message: `${Strings.filterInvalidValue(
                this.key,
                filterValue,
              )}. Use the format <pre>&lt;owner&gt;/&lt;repo&gt;#&lt;number&gt;</pre>.`, // Renders as `<owner>/<repo>#<number>`
            },
          ],
        }
      }
      return {
        ...value,
        valid: true,
      }
    })

    return Promise.resolve(validations)
  }
}
