import {
  FILTER_PRIORITY_DISPLAY_THRESHOLD,
  type FilterBlock,
  type FilterConfig,
  FilterProviderType,
  type FilterQuery,
  type IndexedBlockValueItem,
  NOT_SHOWN,
  type SuppliedFilterProviderOptions,
  ValidationTypes,
} from '@github-ui/filter'
import {TIME_RANGE_VALUES} from '@github-ui/filter/constants/dynamic-filter-values'
import {
  AssigneeFilterProvider,
  BaseUserFilterProvider,
  IsFilterProvider,
  type Issue,
  LabelFilterProvider,
  MilestoneFilterProvider,
  ParentIssueFilterProvider,
  RepositoryFilterProvider,
  StateFilterProvider,
  StaticFilterProvider,
  UpdatedFilterProvider,
  type UserFilterParams,
} from '@github-ui/filter/providers'
import type {ColorName, ColorSet} from '@github-ui/use-named-color'
import {
  CalendarIcon,
  CheckCircleIcon,
  GitPullRequestIcon,
  IssueReopenedIcon,
  IssueTrackedByIcon,
  IssueTracksIcon,
  IterationsIcon,
  MentionIcon,
  NoEntryIcon,
  NumberIcon,
  PersonIcon,
  SingleSelectIcon,
  SkipIcon,
  TypographyIcon,
} from '@primer/octicons-react'

import type {ParentIssue} from '../../api/common-contracts'
import {getGroupingMetadataFromServerGroupValue} from '../../features/grouping/get-grouping-metadata'
import type {IterationGrouping, SingleSelectGrouping} from '../../features/grouping/types'
import {getApiMetadata} from '../../helpers/api-metadata'
import {intervalDatesDescription} from '../../helpers/iterations'
import type {ColumnModel} from '../../models/column-model'
import type {DateColumnModel} from '../../models/column-model/custom/date'
import type {IterationColumnModel} from '../../models/column-model/custom/iteration'
import type {NumberColumnModel} from '../../models/column-model/custom/number'
import type {SingleSelectColumnModel} from '../../models/column-model/custom/single-select'
import type {TextColumnModel} from '../../models/column-model/custom/text'
import type {AssigneesColumnModel} from '../../models/column-model/system/assignees'
import type {LabelsColumnModel} from '../../models/column-model/system/labels'
import type {MilestoneColumnModel} from '../../models/column-model/system/milestone'
import type {ParentIssueColumnModel} from '../../models/column-model/system/parent-issue'
import type {RepositoryColumnModel} from '../../models/column-model/system/repository'
import type {StatusColumnModel} from '../../models/column-model/system/status'
import type {SubIssuesProgressColumnModel} from '../../models/column-model/system/sub-issues-progress'
import type {TitleColumnModel} from '../../models/column-model/system/title'
import {FilterQueryResources} from '../../strings'
import {
  fieldDelimiterValidator,
  MemexAsyncFilterDelimiter,
  MemexStaticFilterDelimiter,
} from './helpers/filter-field-delimiter'
import {getFilterKeyFromColumnName} from './helpers/get-filter-key-from-column-name'
import {getIterationMacros, getTextMacros} from './helpers/macros'

// Regex for an ISO8601 date, which requires 2-digit month and day unlike the default date regex in the StaticFilterProvider
const MEMEX_DATE_REGEX = /^(?:>|<|>=|<=)?(\d{4}-\d{2}-\d{2})?$/
// Regex for dynamic date parsing in Memex, allowing optional time units, unlike the default date regex in the StaticFilterProvider.
const MEMEX_DYNAMIC_DATE_REGEX = /^(?:>|<|>=|<=)?(@[A-Za-z]+)([+-]\d+[mdwqy]?)?$/

// Default priorities for all other filter providers can be found in
// @github-ui/filter/constants/filter-constants.ts
export const FILTER_PRIORITIES = {
  date: NOT_SHOWN,
  iteration: NOT_SHOWN,
  linkedPullRequests: FILTER_PRIORITY_DISPLAY_THRESHOLD,
  milestone: FILTER_PRIORITY_DISPLAY_THRESHOLD,
  type: FILTER_PRIORITY_DISPLAY_THRESHOLD,
  no: FILTER_PRIORITY_DISPLAY_THRESHOLD,
  number: NOT_SHOWN,
  reviewers: FILTER_PRIORITY_DISPLAY_THRESHOLD,
  singleSelect: FILTER_PRIORITY_DISPLAY_THRESHOLD,
  state: NOT_SHOWN,
  text: NOT_SHOWN,
  title: FILTER_PRIORITY_DISPLAY_THRESHOLD,
  subIssuesProgress: FILTER_PRIORITY_DISPLAY_THRESHOLD,
  parentIssue: FILTER_PRIORITY_DISPLAY_THRESHOLD,
  reason: NOT_SHOWN,
  lastUpdated: NOT_SHOWN,
}

const FilterKeys = {
  date: (column: DateColumnModel) => ({
    key: getFilterKeyFromColumnName(column.name),
    displayName: column.name,
    icon: CalendarIcon,
    priority: FILTER_PRIORITIES.date,
    type: FilterProviderType.Date,
  }),
  iteration: (column: IterationColumnModel) => ({
    key: getFilterKeyFromColumnName(column.name),
    displayName: column.name,
    icon: IterationsIcon,
    priority: FILTER_PRIORITIES.iteration,
  }),
  linkedPullRequests: {
    displayName: 'Linked pull requests',
    key: 'linked-pull-requests',
    icon: GitPullRequestIcon,
    description: 'Issue items with a linked pull request',
    priority: FILTER_PRIORITIES.linkedPullRequests,
  },
  no: {
    key: 'no',
    displayName: 'No',
    description: 'Items without a value for the specified field',
    priority: FILTER_PRIORITIES.no,
    icon: NoEntryIcon,
  },
  number: (column: NumberColumnModel) => ({
    key: getFilterKeyFromColumnName(column.name),
    displayName: column.name,
    icon: NumberIcon,
    priority: FILTER_PRIORITIES.number,
    type: FilterProviderType.Number,
  }),
  reviewers: {
    displayName: 'Reviewers',
    key: 'reviewers',
    icon: PersonIcon,
    description: 'Items reviewed by the user',
    priority: FILTER_PRIORITIES.reviewers,
  },
  singleSelect: (column: SingleSelectColumnModel | StatusColumnModel) => ({
    key: getFilterKeyFromColumnName(column.name),
    displayName: column.name,
    icon: SingleSelectIcon,
    priority: FILTER_PRIORITIES.singleSelect,
  }),
  text: (column: TextColumnModel) => ({
    key: getFilterKeyFromColumnName(column.name),
    displayName: column.name,
    icon: TypographyIcon,
    priority: FILTER_PRIORITIES.text,
    type: FilterProviderType.Text,
  }),
  title: (column: TitleColumnModel) => ({
    key: getFilterKeyFromColumnName(column.name),
    displayName: column.name,
    icon: TypographyIcon,
    priority: FILTER_PRIORITIES.title,
    type: FilterProviderType.Text,
  }),
  parentIssue: (column: ParentIssueColumnModel) => ({
    key: 'parent-issue',
    displayName: column.name,
    icon: IssueTrackedByIcon,
    priority: FILTER_PRIORITIES.parentIssue,
    type: FilterProviderType.Text,
  }),
  subIssuesProgress: (column: SubIssuesProgressColumnModel) => ({
    key: 'sub-issues-progress',
    displayName: column.name,
    icon: IssueTracksIcon,
    priority: FILTER_PRIORITIES.subIssuesProgress,
    // We are using "unknown" type here for now, as it's not clear exactly how the semantics of filtering
    // on a percentage should be treated. It's probably similar to a number, but may be slightly different.
    type: FilterProviderType.Unknown,
  }),
  reason: {
    key: 'reason',
    displayName: 'Closed reason',
    priority: FILTER_PRIORITIES.reason,
    icon: MentionIcon,
    description: 'Filter by item closed reason',
  },
  lastUpdated: {
    key: 'last-updated',
    displayName: 'Last updated',
    priority: FILTER_PRIORITIES.lastUpdated,
    icon: CalendarIcon,
    description: 'Date when the item was last updated',
  },
}

const memexDateFormatValidation = (
  provider: string,
  blocks: Array<IndexedBlockValueItem>,
): Array<IndexedBlockValueItem> => {
  return blocks.map(block => {
    if (typeof block.value !== 'string') return block

    // The `@` character denotes a dynamic date range.
    if (block.value.includes('@')) {
      return {...block, valid: MEMEX_DYNAMIC_DATE_REGEX.test(block.value)}
    }

    if (!MEMEX_DATE_REGEX.test(block.value)) {
      return {
        ...block,
        valid: false,
        validations: [
          {
            type: ValidationTypes.InvalidValue,
            message: FilterQueryResources.invalidPwlDateValue(provider, block.value),
          },
        ],
      }
    }

    return block
  })
}

//#region System column filter providers (non-standard)

/*
 * The standard LinkedFilterProvider extends the StaticFilterProvider and accepts a boolean or yes/no value.
 * This would be non-backwards compatible with existing Memex behavior, which is to accept pull request value(s).
 * Since this filter provider needs to be custom to work with the existing `linked-pull-requests` query key anyway,
 * it can extend the StaticFilterProvider and accept a string value until we want to change the behavior.
 */
@MemexStaticFilterDelimiter
export class LinkedPullRequestsFilterProvider extends StaticFilterProvider {
  constructor(options?: SuppliedFilterProviderOptions) {
    super(FilterKeys.linkedPullRequests, [], {
      ...options,
      filterTypes: {hasValue: true, ...options?.filterTypes},
    })
  }
}

/*
 * The standard ReviewedByFilterProvider has the query key `reviewed-by:` which does not work for Memex at present.
 */
@MemexAsyncFilterDelimiter
export class ReviewersFilterProvider extends BaseUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    super(filterParams, FilterKeys.reviewers, options)
  }
}

//#region Custom column filter providers

export class DateFilterProvider extends StaticFilterProvider {
  constructor(columnModel: DateColumnModel) {
    const filterKey = FilterKeys.date(columnModel)
    super(filterKey, TIME_RANGE_VALUES, {filterTypes: {hasValue: true}})

    // Overrides the StaticFilterProvider's default filter type to ensure valid date filter field values.
    this.type = FilterProviderType.Date
  }

  override async validateFilterBlockValues(
    filterQuery: FilterQuery,
    block: FilterBlock,
    values: Array<IndexedBlockValueItem>,
    config: FilterConfig,
  ): Promise<Array<IndexedBlockValueItem>> {
    const filterBlockValues = await super.validateFilterBlockValues(filterQuery, block, values, config)
    return fieldDelimiterValidator(block, memexDateFormatValidation(this.key, filterBlockValues))
  }
}

@MemexStaticFilterDelimiter
export class IterationFilterProvider extends StaticFilterProvider {
  constructor(columnModel: IterationColumnModel) {
    const filterKey = FilterKeys.iteration(columnModel)
    const {iterations, completedIterations} = columnModel.settings.configuration
    const iterationMacros = getIterationMacros(columnModel.name)
    const filterValues = [...iterations, ...completedIterations].map((iteration, idx) => {
      const serverMetadata = getGroupingMetadataFromServerGroupValue(columnModel, iteration.id) as IterationGrouping
      const groupMetadata =
        serverMetadata && serverMetadata.kind !== 'empty' ? serverMetadata.value.iteration : iteration
      const {title, titleHtml, startDate, duration} = groupMetadata

      return {
        ariaLabel: title,
        value: title,
        priority: idx + iterationMacros.length + 2, // +2 to accommodate suggestion helpers
        displayName: titleHtml,
        description: intervalDatesDescription({startDate, duration}),
        inlineDescription: false,
      }
    })
    super(filterKey, [...iterationMacros, ...filterValues], {filterTypes: {hasValue: true}})
  }
}

@MemexStaticFilterDelimiter
export class NumberFilterProvider extends StaticFilterProvider {
  constructor(columnModel: NumberColumnModel) {
    const filterKey = FilterKeys.number(columnModel)
    super(filterKey, [], {filterTypes: {hasValue: true}})
  }
}

@MemexStaticFilterDelimiter
export class SingleSelectFilterProvider extends StaticFilterProvider {
  constructor(
    columnModel: StatusColumnModel | SingleSelectColumnModel,
    getPresentationalColor: (name: ColorName) => ColorSet,
    options?: SuppliedFilterProviderOptions,
  ) {
    const filterKey = FilterKeys.singleSelect(columnModel)
    const filterValues = (columnModel.settings.options ?? []).map((value, idx) => {
      const serverMetadata = getGroupingMetadataFromServerGroupValue(columnModel, value.name) as SingleSelectGrouping
      const groupMetadata = serverMetadata && serverMetadata.kind !== 'empty' ? serverMetadata.value.option : value
      const {descriptionHtml, name, nameHtml, color} = groupMetadata
      // The Filter component only supports a single iconColor.
      // The legacy filter combined a darker border with a lighter fill.
      // Using only the lighter fill in this context is too light,
      // so we opt for the border color here.
      const iconColor = getPresentationalColor(color)?.border

      return {
        ariaLabel: name,
        value: name,
        priority: idx + 2, // +1 to accommodate helpers
        displayName: nameHtml,
        description: descriptionHtml,
        inlineDescription: false,
        iconColor,
      }
    })

    super(filterKey, filterValues, {...options, filterTypes: {hasValue: true, ...options?.filterTypes}})
  }
}

@MemexStaticFilterDelimiter
export class TextFilterProvider extends StaticFilterProvider {
  constructor(columnModel: TextColumnModel) {
    const filterKey = FilterKeys.text(columnModel)
    const textMacros = getTextMacros(columnModel.name)
    super(filterKey, [...textMacros], {filterTypes: {hasValue: true}})
  }
}

@MemexStaticFilterDelimiter
export class TitleFilterProvider extends StaticFilterProvider {
  constructor(columnModel: TitleColumnModel) {
    const filterKey = FilterKeys.title(columnModel)
    const textMacros = getTextMacros(columnModel.name)
    // All project items have a title, so we omit the 'Has' and 'No' filter types.
    super(filterKey, [...textMacros], {filterTypes: {hasValue: false, valueless: false}})
  }
}

@MemexStaticFilterDelimiter
export class SubIssuesProgressFilterProvider extends StaticFilterProvider {
  constructor(columnModel: SubIssuesProgressColumnModel, options?: SuppliedFilterProviderOptions) {
    const filterKey = FilterKeys.subIssuesProgress(columnModel)
    super(filterKey, [], {...options})
  }
}

function getSuggestionEndpoint() {
  return getApiMetadata('memex-filter-suggestions-api-data')?.url
}

function buildProviderContext(columnModel: ColumnModel) {
  return new URLSearchParams({
    field_id: columnModel.databaseId?.toString(),
  })
}

@MemexAsyncFilterDelimiter
export class MemexAssigneeFilterProvider extends AssigneeFilterProvider {
  constructor(
    columnModel: AssigneesColumnModel,
    filterParams: UserFilterParams,
    options?: SuppliedFilterProviderOptions,
  ) {
    super(filterParams, options)

    this.suggestionEndpoint = getSuggestionEndpoint()
    this.providerContext = buildProviderContext(columnModel)
  }
}

@MemexAsyncFilterDelimiter
export class MemexLabelFilterProvider extends LabelFilterProvider {
  constructor(columnModel: LabelsColumnModel, options?: SuppliedFilterProviderOptions) {
    super(options)

    this.suggestionEndpoint = getSuggestionEndpoint()
    this.providerContext = buildProviderContext(columnModel)
  }
}

@MemexAsyncFilterDelimiter
export class MemexMilestoneFilterProvider extends MilestoneFilterProvider {
  constructor(columnModel: MilestoneColumnModel, options?: SuppliedFilterProviderOptions) {
    super(options)

    this.suggestionEndpoint = getSuggestionEndpoint()
    this.providerContext = buildProviderContext(columnModel)
  }
}

@MemexAsyncFilterDelimiter
export class MemexParentIssueFilterProvider extends ParentIssueFilterProvider {
  constructor(columnModel: ParentIssueColumnModel, options?: SuppliedFilterProviderOptions) {
    const filterKey = FilterKeys.parentIssue(columnModel)
    super(filterKey, {
      filterTypes: {...options?.filterTypes},
    })

    this.suggestionEndpoint = getSuggestionEndpoint()
    this.providerContext = buildProviderContext(columnModel)
  }

  override async fetchSuggestions(): Promise<Array<Issue> | null> {
    const cachedSuggestions = this.suggestionCache.get('')
    if (cachedSuggestions) {
      return cachedSuggestions
    }

    const endpoint = new URL(this.suggestionEndpoint, window.location.origin)
    endpoint.search = this.providerContext?.toString() || ''

    const response = await this.fetchData(endpoint.toString())

    if (!response || !response.ok) {
      return null
    }

    const json = await response.json()
    const suggestions = json.suggestions as Array<ParentIssue>

    // Prefer more recently created issues at the top of the list.
    const sorted = suggestions.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)) satisfies Array<Issue>

    this.suggestionCache.set('', sorted)

    return sorted
  }

  override validateFilterValue(): Promise<null> {
    return Promise.resolve(null)
  }
}

@MemexAsyncFilterDelimiter
export class MemexRepositoryFilterProvider extends RepositoryFilterProvider {
  constructor(columnModel: RepositoryColumnModel, options?: SuppliedFilterProviderOptions) {
    super(options)

    this.suggestionEndpoint = getSuggestionEndpoint()
    this.providerContext = buildProviderContext(columnModel)
  }
}

@MemexAsyncFilterDelimiter
export class MemexReviewersFilterProvider extends ReviewersFilterProvider {}

@MemexStaticFilterDelimiter
export class MemexIsFilterProvider extends IsFilterProvider {}

@MemexStaticFilterDelimiter
export class MemexStateFilterProvider extends StateFilterProvider {}

@MemexStaticFilterDelimiter
export class ReasonFilterProvider extends StaticFilterProvider {
  constructor() {
    const filterValues = [
      {
        value: 'completed',
        displayName: 'Completed',
        priority: 1,
        icon: CheckCircleIcon,
        iconColor: 'var(--fgColor-done, var(--color-done-fg))',
      },
      {
        value: 'not-planned',
        displayName: 'Not planned',
        priority: 2,
        icon: SkipIcon,
        iconColor: 'var(--fgColor-muted, var(--color-neutral-emphasis))',
      },
      {
        value: 'duplicate',
        displayName: 'Duplicate',
        priority: 3,
        icon: SkipIcon,
        iconColor: 'var(--fgColor-muted, var(--color-neutral-emphasis))',
      },
      {
        value: 'reopened',
        displayName: 'Reopened',
        priority: 4,
        icon: IssueReopenedIcon,
        iconColor: 'var(--fgColor-open, var(--color-open-fg))',
      },
    ]

    super(FilterKeys.reason, filterValues, {filterTypes: {valueless: false}})
  }
}

@MemexStaticFilterDelimiter
export class LastUpdatedFilterProvider extends StaticFilterProvider {
  constructor() {
    const filterValues = [
      {
        ariaLabel: '7 days',
        value: '7days',
        priority: 1,
        displayName: '7 or more days ago',
      },
      {
        ariaLabel: '14 days',
        value: '14days',
        priority: 2,
        displayName: '14 or more days ago',
      },
      {
        ariaLabel: '21 days',
        value: '21days',
        priority: 3,
        displayName: '21 or more days ago',
      },
    ]

    super(FilterKeys.lastUpdated, filterValues, {filterTypes: {valueless: false}})
  }
}

export class MemexUpdatedFilterProvider extends UpdatedFilterProvider {
  override async validateFilterBlockValues(
    filterQuery: FilterQuery,
    block: FilterBlock,
    values: Array<IndexedBlockValueItem>,
    config: FilterConfig,
  ): Promise<Array<IndexedBlockValueItem>> {
    const filterBlockValues = await super.validateFilterBlockValues(filterQuery, block, values, config)
    return fieldDelimiterValidator(block, memexDateFormatValidation(this.key, filterBlockValues))
  }
}
