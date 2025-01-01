import {MemexColumnDataType} from '../api/columns/contracts/memex-column'

/**
 * Defines the capabilities a column can have.
 *
 * This is a work in progress - eventually all column capabilities such as
 * grouping, sorting, filtering, and other functionality should be centrally
 * located here rather than spread across multiple configuration files.
 *
 * When adding a new capability, add it here as a boolean property.
 */
type ColumnCapabilities = {
  // Display capabilities
  isBoardCardLabelable: boolean
  isCopyable: boolean // This should only be false for columns in development

  // Organization capabilities
  isSortable: boolean
  isFilterable: boolean
  isGroupable: boolean
  isVerticalGroup: boolean
  isSliceable: boolean

  // Editing capabilities
  isValueClearable: boolean
  isValueEditable: boolean
  isValueBulkEditable: boolean
  isValueEditableFromFilter: boolean // Describes whether a column value can be set from a derived filter value when adding an item
  isPasteable: boolean

  // Describes whether the filter bar fetches async suggestions for this column
  hasRemoteFilterSuggestions: boolean
}

const AssigneeColumnCapabilities = {
  isBoardCardLabelable: false,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: true,
  isVerticalGroup: false,
  isSliceable: true,
  isValueClearable: true,
  isValueEditable: true,
  isValueBulkEditable: true,
  isPasteable: true,
  isValueEditableFromFilter: true,
  hasRemoteFilterSuggestions: true,
} as const

const DateColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: true,
  isVerticalGroup: false,
  isSliceable: true,
  isValueClearable: true,
  isValueEditable: true,
  isValueEditableFromFilter: true,
  isPasteable: true,
  isValueBulkEditable: true,
  hasRemoteFilterSuggestions: true,
} as const

const IssueTypeColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: true,
  isVerticalGroup: false,
  isSliceable: true,
  isValueClearable: true,
  isValueEditable: true,
  isValueBulkEditable: true,
  isPasteable: true,
  isValueEditableFromFilter: false,
  hasRemoteFilterSuggestions: true,
} as const

const IterationColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: true,
  isVerticalGroup: true,
  isSliceable: true,
  isValueClearable: true,
  isValueEditable: true,
  isValueBulkEditable: true,
  isPasteable: true,
  isValueEditableFromFilter: true,
  hasRemoteFilterSuggestions: false,
} as const

const LabelColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: false, // Grouping by Label name (regardless of repo) is supported on the server, but not the client
  isVerticalGroup: false,
  isSliceable: true,
  isValueClearable: true,
  isValueEditable: true,
  isPasteable: true,
  isValueBulkEditable: true,
  isValueEditableFromFilter: true,
  hasRemoteFilterSuggestions: true,
} as const

const LinkedPullRequestsColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: false,
  isVerticalGroup: false,
  isSliceable: false,
  isValueClearable: false,
  isValueEditable: false,
  isValueBulkEditable: false,
  isPasteable: false,
  isValueEditableFromFilter: false,
  hasRemoteFilterSuggestions: true,
} as const

const MilestoneColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: true,
  isVerticalGroup: false,
  isSliceable: true,
  isValueClearable: true,
  isValueEditable: true,
  isValueBulkEditable: true,
  isPasteable: true,
  isValueEditableFromFilter: true,
  hasRemoteFilterSuggestions: true,
} as const

const NumberColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: true,
  isVerticalGroup: false,
  isSliceable: true,
  isValueClearable: true,
  isValueEditable: true,
  isValueBulkEditable: true,
  isPasteable: true,
  isValueEditableFromFilter: true,
  hasRemoteFilterSuggestions: true,
} as const

const ParentIssueColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: true,
  isVerticalGroup: false,
  isSliceable: true,
  isValueClearable: true,
  isValueEditable: true,
  isValueBulkEditable: true,
  isPasteable: true,
  isValueEditableFromFilter: true,
  hasRemoteFilterSuggestions: true,
} as const

const RepositoryColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: true,
  isVerticalGroup: false,
  isSliceable: true,
  isValueClearable: false,
  isValueEditable: true,
  isValueBulkEditable: false,
  isPasteable: false,
  isValueEditableFromFilter: false,
  hasRemoteFilterSuggestions: true,
} as const

const ReviewersColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: false,
  isVerticalGroup: false,
  isSliceable: false,
  isValueClearable: false,
  isValueEditable: false,
  isValueBulkEditable: false,
  isPasteable: false,
  isValueEditableFromFilter: false,
  hasRemoteFilterSuggestions: true,
} as const

const SingleSelectColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: true,
  isVerticalGroup: true,
  isSliceable: true,
  isValueClearable: true,
  isValueEditable: true,
  isValueBulkEditable: true,
  isPasteable: true,
  isValueEditableFromFilter: true,
  hasRemoteFilterSuggestions: false,
} as const

const SubIssuesProgressColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: false,
  isVerticalGroup: false,
  isSliceable: false,
  isValueClearable: false,
  isValueEditable: false,
  isValueBulkEditable: false,
  isPasteable: false,
  isValueEditableFromFilter: false,
  hasRemoteFilterSuggestions: false,
} as const

const TextColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: true,
  isVerticalGroup: false,
  isSliceable: true,
  isValueClearable: true,
  isValueEditable: true,
  isValueBulkEditable: true,
  isPasteable: true,
  isValueEditableFromFilter: true,
  hasRemoteFilterSuggestions: true,
} as const

const TitleColumnCapabilities = {
  isBoardCardLabelable: false,
  isCopyable: true,
  isSortable: true,
  isFilterable: true,
  isGroupable: false,
  isVerticalGroup: false,
  isSliceable: false,
  isValueClearable: false,
  isValueEditable: true,
  isPasteable: false,
  isValueBulkEditable: false,
  isValueEditableFromFilter: false,
  hasRemoteFilterSuggestions: false,
} as const

const TracksColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: false,
  isFilterable: false,
  isGroupable: false,
  isVerticalGroup: false,
  isSliceable: false,
  isValueClearable: false,
  isValueEditable: false,
  isValueBulkEditable: false,
  isPasteable: false,
  isValueEditableFromFilter: false,
  hasRemoteFilterSuggestions: false,
} as const

const TrackedByColumnCapabilities = {
  isBoardCardLabelable: true,
  isCopyable: true,
  isSortable: false,
  isFilterable: false,
  isGroupable: false,
  isVerticalGroup: false,
  isSliceable: false,
  isValueEditable: false,
  isValueClearable: false,
  isValueBulkEditable: false,
  isPasteable: false,
  isValueEditableFromFilter: false,
  hasRemoteFilterSuggestions: false,
} as const

/**
 * Maps each column type to its capabilities.
 * When adding a new column type to the system, add an entry here
 * with its appropriate capabilities.
 */
const columnCapabilitiesMap: {
  [key in MemexColumnDataType]: ColumnCapabilities
} = {
  [MemexColumnDataType.Assignees]: AssigneeColumnCapabilities,
  [MemexColumnDataType.Date]: DateColumnCapabilities,
  [MemexColumnDataType.IssueType]: IssueTypeColumnCapabilities,
  [MemexColumnDataType.Iteration]: IterationColumnCapabilities,
  [MemexColumnDataType.Labels]: LabelColumnCapabilities,
  [MemexColumnDataType.LinkedPullRequests]: LinkedPullRequestsColumnCapabilities,
  [MemexColumnDataType.Milestone]: MilestoneColumnCapabilities,
  [MemexColumnDataType.Number]: NumberColumnCapabilities,
  [MemexColumnDataType.ParentIssue]: ParentIssueColumnCapabilities,
  [MemexColumnDataType.Repository]: RepositoryColumnCapabilities,
  [MemexColumnDataType.Reviewers]: ReviewersColumnCapabilities,
  [MemexColumnDataType.SingleSelect]: SingleSelectColumnCapabilities,
  [MemexColumnDataType.SubIssuesProgress]: SubIssuesProgressColumnCapabilities,
  [MemexColumnDataType.Text]: TextColumnCapabilities,
  [MemexColumnDataType.Title]: TitleColumnCapabilities,
  [MemexColumnDataType.Tracks]: TracksColumnCapabilities,
  [MemexColumnDataType.TrackedBy]: TrackedByColumnCapabilities,
}

export function getCapableColumns(prop: keyof ColumnCapabilities): Array<MemexColumnDataType> {
  return (Object.keys(columnCapabilitiesMap) as Array<MemexColumnDataType>).filter(
    key => columnCapabilitiesMap[key][prop],
  )
}

/**
 * Explicit type mapping for all column capabilities.
 * This is technically redundant with columnCapabilitiesMap, but provides
 * stronger compile-time type checking and enables type extraction utilities.
 *
 * When adding a new column type, you must add it here to keep the types in sync.
 */
type ColumnCapabilitiesType = {
  [MemexColumnDataType.Assignees]: typeof AssigneeColumnCapabilities
  [MemexColumnDataType.Date]: typeof DateColumnCapabilities
  [MemexColumnDataType.IssueType]: typeof IssueTypeColumnCapabilities
  [MemexColumnDataType.Iteration]: typeof IterationColumnCapabilities
  [MemexColumnDataType.Labels]: typeof LabelColumnCapabilities
  [MemexColumnDataType.LinkedPullRequests]: typeof LinkedPullRequestsColumnCapabilities
  [MemexColumnDataType.Milestone]: typeof MilestoneColumnCapabilities
  [MemexColumnDataType.Number]: typeof NumberColumnCapabilities
  [MemexColumnDataType.ParentIssue]: typeof ParentIssueColumnCapabilities
  [MemexColumnDataType.Repository]: typeof RepositoryColumnCapabilities
  [MemexColumnDataType.Reviewers]: typeof ReviewersColumnCapabilities
  [MemexColumnDataType.SingleSelect]: typeof SingleSelectColumnCapabilities
  [MemexColumnDataType.SubIssuesProgress]: typeof SubIssuesProgressColumnCapabilities
  [MemexColumnDataType.Text]: typeof TextColumnCapabilities
  [MemexColumnDataType.Title]: typeof TitleColumnCapabilities
  [MemexColumnDataType.Tracks]: typeof TracksColumnCapabilities
  [MemexColumnDataType.TrackedBy]: typeof TrackedByColumnCapabilities
}

export type ExtractColumnCapabilityType<Property extends keyof ColumnCapabilitiesType[keyof ColumnCapabilitiesType]> = {
  [K in keyof ColumnCapabilitiesType]: ColumnCapabilitiesType[K][Property] extends true ? K : never
}[keyof ColumnCapabilitiesType]

// Board card rendering

const boardLabelableColumns = getCapableColumns('isBoardCardLabelable')

type BoardLabelableColumn = ExtractColumnCapabilityType<'isBoardCardLabelable'>

export function isBoardLabelableColumn(column: MemexColumnDataType): column is BoardLabelableColumn {
  return boardLabelableColumns.includes(column)
}

// Sorting

const sortableColumns = getCapableColumns('isSortable')

type SortableColumn = ExtractColumnCapabilityType<'isSortable'>

export function isSortableColumn(column: MemexColumnDataType): column is SortableColumn {
  return sortableColumns.includes(column)
}

// Filtering

const filterableColumns = getCapableColumns('isFilterable')

type FilterableColumn = ExtractColumnCapabilityType<'isFilterable'>

export function isFilterableColumn(column: MemexColumnDataType): column is FilterableColumn {
  return filterableColumns.includes(column)
}

// Grouping

const groupableColumns = getCapableColumns('isGroupable')

export type GroupableColumn = ExtractColumnCapabilityType<'isGroupable'>

export function isGroupableColumn(column: MemexColumnDataType): column is GroupableColumn {
  return groupableColumns.includes(column)
}

const verticalGroupColumns = getCapableColumns('isVerticalGroup')

export type VerticalGroupColumn = ExtractColumnCapabilityType<'isVerticalGroup'>

export function isVerticalGroupColumn(column: MemexColumnDataType): column is VerticalGroupColumn {
  return verticalGroupColumns.includes(column)
}

// Slicing

const slicableColumns = getCapableColumns('isSliceable')

export type SlicableColumn = ExtractColumnCapabilityType<'isSliceable'>

export function isSliceableColumn(column: MemexColumnDataType): column is SlicableColumn {
  return slicableColumns.includes(column)
}

export type GroupableMetadataType = GroupableColumn | SlicableColumn

export function isGroupMetadataType(column: MemexColumnDataType): column is GroupableMetadataType {
  return isGroupableColumn(column) || slicableColumns.includes(column)
}

// Editing

const valueEditableColumns = getCapableColumns('isValueEditable')

export type ValueEditableColumn = ExtractColumnCapabilityType<'isValueEditable'>

export function isValueEditableColumn(column: MemexColumnDataType): column is ValueEditableColumn {
  return valueEditableColumns.includes(column)
}

const bulkValueEditableColumns = getCapableColumns('isValueBulkEditable')

export type BulkValueEditableColumn = ExtractColumnCapabilityType<'isValueBulkEditable'>

export function isValueBulkEditableColumn(column: MemexColumnDataType): column is ValueEditableColumn {
  return bulkValueEditableColumns.includes(column)
}

const valueClearableColumns = getCapableColumns('isValueClearable')

type ClearableColumn = ExtractColumnCapabilityType<'isValueClearable'>

export function isValueClearableColumn(column: MemexColumnDataType): column is ClearableColumn {
  return valueClearableColumns.includes(column)
}

const valueEditableFromFilterColumns = getCapableColumns('isValueEditableFromFilter')

export type ValueEditableFromFilterColumn = ExtractColumnCapabilityType<'isValueEditableFromFilter'>

export function isValueEditableFromFilterColumn(column: MemexColumnDataType): column is ValueEditableFromFilterColumn {
  return valueEditableFromFilterColumns.includes(column)
}

// Remote filter suggestions (does the filter-bar fetch async suggestions)

const remoteFilterSuggestionsColumn = getCapableColumns('hasRemoteFilterSuggestions')

type RemoteFilterSuggestionsColumn = ExtractColumnCapabilityType<'hasRemoteFilterSuggestions'>

export function isRemoteFilterSuggestionsColumn(column: MemexColumnDataType): column is RemoteFilterSuggestionsColumn {
  return remoteFilterSuggestionsColumn.includes(column)
}

const copyableColumns = getCapableColumns('isCopyable')

export type CopyableColumn = ExtractColumnCapabilityType<'isCopyable'>

export function isCopyableColumn(column: MemexColumnDataType): column is CopyableColumn {
  return copyableColumns.includes(column)
}

const pasteableColumns = getCapableColumns('isPasteable')

export type PasteableColumn = ExtractColumnCapabilityType<'isPasteable'>

export function isPasteableColumn(column: MemexColumnDataType): column is PasteableColumn {
  return pasteableColumns.includes(column)
}
