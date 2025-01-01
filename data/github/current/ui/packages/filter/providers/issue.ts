import {fuzzyScore} from '@github-ui/fuzzy-score/fuzzy-score'
import {IssueClosedIcon, IssueOpenedIcon, SkipIcon} from '@primer/octicons-react'

import {FILTER_KEYS, INDETERMINANT} from '../constants/filter-constants'
import type {FilterQuery} from '../filter-query'
import {
  type AnyBlock,
  type ARIAFilterSuggestion,
  type FilterConfig,
  type FilterKey,
  type FilterProvider,
  FilterProviderType,
  type FilterValueData,
  FilterValueType,
  type IndexedBlockValueItem,
  type MutableFilterBlock,
  type SuppliedFilterProviderOptions,
  type ValueRowProps,
} from '../types'
import {getFilterValue, getUnescapedFilterValue} from '../utils'
import {ValueIcon} from '../utils/ValueIcon'
import {AsyncFilterProvider} from './async'

const ISSUE_SUGGESTION_ENDPOINT = '/_filter/issues'
const ISSUE_VALIDATION_ENDPOINT = '/_filter/issues/validate'

export const IssueState = {
  Open: 'open',
  Closed: 'closed',
} as const

export const IssueStateReason = {
  NotPlanned: 'not_planned',
  Completed: 'completed',
  Reopened: 'reopened',
  Duplicate: 'duplicate',
} as const

export type Issue = {
  title: string
  titleHtml: string
  nwoReference: string
  state: (typeof IssueState)[keyof typeof IssueState]
  stateReason?: (typeof IssueStateReason)[keyof typeof IssueStateReason]
  number: number
}

export class BaseIssueFilterProvider extends AsyncFilterProvider<Issue> implements FilterProvider {
  constructor(filterKey: FilterKey, options?: SuppliedFilterProviderOptions) {
    super(filterKey, options)
    this.suggestionEndpoint = ISSUE_SUGGESTION_ENDPOINT
    this.validationEndpoint = ISSUE_VALIDATION_ENDPOINT
    this.type = FilterProviderType.Select
  }

  async getSuggestions(
    filterQuery: FilterQuery,
    filterBlock: AnyBlock | MutableFilterBlock,
    config: FilterConfig,
    caretIndex?: number | null,
  ) {
    return this.processSuggestions(filterQuery, filterBlock, this.processSuggestion.bind(this), caretIndex)
  }

  getIconData(issue: Issue) {
    if (issue.state === IssueState.Open)
      return {icon: IssueOpenedIcon, iconColor: 'var(--fgColor-success, var(--color-success-fg))'}
    if (issue.stateReason === IssueStateReason.NotPlanned)
      return {icon: SkipIcon, iconColor: 'var(-fgColor-muted, var(--color-neutral-emphasis))'}
    return {icon: IssueClosedIcon, iconColor: 'var(--fgColor-done, var(--color-done-fg))'}
  }

  private processSuggestion(issue: Issue, query: string): ARIAFilterSuggestion {
    const {title, titleHtml, nwoReference} = issue
    let priority = 3

    if (query) {
      if (title) priority -= fuzzyScore(query, title)
      if (nwoReference) priority -= fuzzyScore(query, nwoReference)
    }

    return {
      type: FilterValueType.Value,
      displayName: titleHtml ?? title,
      ariaLabel: `${title}, ${this.displayName}`,
      description: nwoReference,
      inlineDescription: false,
      value: nwoReference ?? '',
      priority,
      ...this.getIconData(issue),
    }
  }

  override validateValue(
    filterQuery: FilterQuery,
    value: IndexedBlockValueItem,
    issue: Issue | null,
  ): false | Partial<IndexedBlockValueItem> | null | undefined {
    const extractedValue = getUnescapedFilterValue(value.value)
    if (!extractedValue) return false

    if (issue) {
      return {
        displayName: issue.title,
        value: extractedValue,
      }
    }

    if (!filterQuery.context.repo && !filterQuery.context.org) {
      return {
        value: INDETERMINANT,
      }
    }

    return false
  }

  getValueRowProps(value: FilterValueData): ValueRowProps {
    return {
      text: value.displayName ?? getFilterValue(value.value) ?? '',
      description: value.description,
      descriptionVariant: 'block',
      leadingVisual: ValueIcon({value, providerIcon: this.icon, squareIcon: true}),
    }
  }
}

export class ParentIssueFilterProvider extends BaseIssueFilterProvider {
  constructor(filterKey?: FilterKey, options?: SuppliedFilterProviderOptions) {
    super(filterKey || FILTER_KEYS.parentIssue, options)
    this.providerContext = new URLSearchParams({parent: 'true'})
  }
}
