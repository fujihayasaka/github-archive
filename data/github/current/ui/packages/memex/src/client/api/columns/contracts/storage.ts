// This module contains the type declarations for storing and updating data
// within the application
import type {
  ExtendedRepository,
  IAssignee,
  IssueType,
  Label,
  LinkedPullRequest,
  Milestone,
  ParentIssue,
  Review,
  SubIssuesProgress,
} from '../../common-contracts'
import type {TrackedByItem} from '../../issues-graph/contracts'
import type {DateValue, ServerDateValue} from './date'
import type {IterationValue} from './iteration'
import type {MemexColumnDataType, SystemColumnId} from './memex-column'
import type {NumericValue} from './number'
import type {SingleSelectValue} from './single-select'
import type {EnrichedText} from './text'
import type {
  DraftIssueTitleValue,
  IssueTitleValue,
  PullRequestTitleValue,
  RedactedItemTitleValue,
  TitleUpdateValue,
  TitleValue,
  TitleValueWithContentType,
} from './title'
import type {Progress} from './tracks'

// ============================================================================
// ID Types
// ============================================================================

type CustomColumnId = number
type IdType = number | ''

// ============================================================================
// Base Column Structures
// ============================================================================

/**
 * Mapping of MemexColumnDataType to its corresponding value type.
 * Add new entries here as new column types are added to the system.
 */
export type DataTypeToValueMap = {
  [MemexColumnDataType.Assignees]: Array<IAssignee>
  [MemexColumnDataType.Labels]: Array<Label>
  [MemexColumnDataType.LinkedPullRequests]: Array<LinkedPullRequest>
  [MemexColumnDataType.IssueType]: IssueType
  [MemexColumnDataType.Milestone]: Milestone
  [MemexColumnDataType.ParentIssue]: ParentIssue
  [MemexColumnDataType.Repository]: ExtendedRepository
  [MemexColumnDataType.Reviewers]: Array<Review>
  [MemexColumnDataType.SingleSelect]: SingleSelectValue
  [MemexColumnDataType.SubIssuesProgress]: SubIssuesProgress
  [MemexColumnDataType.Tracks]: Progress
  [MemexColumnDataType.TrackedBy]: Array<TrackedByItem>
  [MemexColumnDataType.Title]: TitleValue
  [MemexColumnDataType.Iteration]: IterationValue
  [MemexColumnDataType.Text]: EnrichedText
  [MemexColumnDataType.Number]: NumericValue
  [MemexColumnDataType.Date]: ServerDateValue
}

/**
 * ColumnTemplate defines the structure for column data types in the Memex system
 * This template is used to create consistent type definitions for both system columns and custom columns
 *
 * @template ID - The unique identifier type for the column
 *                (SystemColumnId for system columns or number for custom columns)
 * @template T - The data type of the column's value
 *               (e.g., Array<IAssignee> for Assignees, SingleSelectValue for Status, etc.)
 * @template DT - The data type identifier from MemexColumnDataType
 *                (e.g., MemexColumnDataType.Assignees for Assignees column)
 */

type ColumnTemplate<ID, DT extends MemexColumnDataType, V = DataTypeToValueMap[DT]> = {
  /** The column's data type identifier from MemexColumnDataType */
  dataType: DT
  /** The expected value type for this column, non-nullable */
  value: V
  /** The structure of the column data as stored in the system */
  columnData: {
    /** The unique identifier of the column this data belongs to */
    memexProjectColumnId: ID
    /**
     * The actual value for this column, may be null when empty
     * Type matches the column's expected value type T
     */
    value: V | null
  }
}

type CustomColumnTemplate<DT extends MemexColumnDataType> = ColumnTemplate<CustomColumnId, DT>

// ============================================================================
// System Column Definitions
// ============================================================================

export type SystemColumnMap = {
  [SystemColumnId.Assignees]: ColumnTemplate<typeof SystemColumnId.Assignees, typeof MemexColumnDataType.Assignees>
  [SystemColumnId.Labels]: ColumnTemplate<typeof SystemColumnId.Labels, typeof MemexColumnDataType.Labels>
  [SystemColumnId.LinkedPullRequests]: ColumnTemplate<
    typeof SystemColumnId.LinkedPullRequests,
    typeof MemexColumnDataType.LinkedPullRequests
  >
  [SystemColumnId.IssueType]: ColumnTemplate<typeof SystemColumnId.IssueType, typeof MemexColumnDataType.IssueType>
  [SystemColumnId.Milestone]: ColumnTemplate<typeof SystemColumnId.Milestone, typeof MemexColumnDataType.Milestone>
  [SystemColumnId.ParentIssue]: ColumnTemplate<
    typeof SystemColumnId.ParentIssue,
    typeof MemexColumnDataType.ParentIssue
  >
  [SystemColumnId.Repository]: ColumnTemplate<typeof SystemColumnId.Repository, typeof MemexColumnDataType.Repository>
  [SystemColumnId.Reviewers]: ColumnTemplate<typeof SystemColumnId.Reviewers, typeof MemexColumnDataType.Reviewers>
  [SystemColumnId.Status]: ColumnTemplate<typeof SystemColumnId.Status, typeof MemexColumnDataType.SingleSelect>
  [SystemColumnId.SubIssuesProgress]: ColumnTemplate<
    typeof SystemColumnId.SubIssuesProgress,
    typeof MemexColumnDataType.SubIssuesProgress
  >
  /**
   * Title column has unique characteristics:
   * 1. Value is required (non-nullable)
   * 2. ContentType is attached to column values client-side for easier type discrimination
   */
  [SystemColumnId.Title]: {
    dataType: typeof MemexColumnDataType.Title
    value: TitleValueWithContentType
    columnData: {
      memexProjectColumnId: typeof SystemColumnId.Title
      value: DataTypeToValueMap[typeof MemexColumnDataType.Title]
    }
  }
  [SystemColumnId.Tracks]: ColumnTemplate<typeof SystemColumnId.Tracks, typeof MemexColumnDataType.Tracks>
  [SystemColumnId.TrackedBy]: ColumnTemplate<typeof SystemColumnId.TrackedBy, typeof MemexColumnDataType.TrackedBy>
}

// ============================================================================
// Custom Column Definitions
// ============================================================================

export type CustomColumnMap = {
  [MemexColumnDataType.Iteration]: CustomColumnTemplate<typeof MemexColumnDataType.Iteration>
  [MemexColumnDataType.Text]: CustomColumnTemplate<typeof MemexColumnDataType.Text>
  [MemexColumnDataType.Number]: CustomColumnTemplate<typeof MemexColumnDataType.Number>
  [MemexColumnDataType.Date]: CustomColumnTemplate<typeof MemexColumnDataType.Date>
  [MemexColumnDataType.SingleSelect]: CustomColumnTemplate<typeof MemexColumnDataType.SingleSelect>
}

// ============================================================================
// Column Data Type Accessors and Utilities
// ============================================================================

export type CustomColumnKind = keyof CustomColumnMap
export type GetColumnDataBySystemId<ID extends SystemColumnId> = SystemColumnMap[ID]['columnData']
export type GetColumnValueBySystemId<ID extends SystemColumnId> = SystemColumnMap[ID]['value']
export type GetColumnDataTypeBySystemId<ID extends SystemColumnId> = SystemColumnMap[ID]['dataType']
export type GetColumnDataByCustomColumnDataType<T extends CustomColumnKind> = CustomColumnMap[T]['columnData']
export type GetColumnValueByCustomColumnDataType<T extends CustomColumnKind> = CustomColumnMap[T]['value']

export type SystemColumnData = SystemColumnMap[SystemColumnId]['columnData']
export type CustomColumnData = CustomColumnMap[CustomColumnKind]['columnData']
export type MemexColumnData = CustomColumnData | SystemColumnData
export type MemexColumnDataValue = MemexColumnData['value']
export type CustomColumnValueType = CustomColumnMap[CustomColumnKind]['value'] | undefined
export type ColumnData = {
  [K in SystemColumnId]?: SystemColumnMap[K]['value']
} & {
  [id: CustomColumnId]: CustomColumnValueType
}

/**
 * Maps a MemexColumnDataType to its corresponding column data structure.
 *
 * This utility type returns a union of all possible columnData structures for a given data type.
 * For data types that can exist in both system and custom columns (like SingleSelect),
 * it returns a union of both variants.
 *
 * Example for SingleSelect:
 * ```typescript
 * {
 *   // System column variant (Status)
 *   memexProjectColumnId: typeof SystemColumnId.Status;
 *   value: SingleSelectValue | null;
 * } | {
 *   // Custom column variant
 *   memexProjectColumnId: number;
 *   value: SingleSelectValue | null;
 * }
 * ```
 *
 * @template DT - The MemexColumnDataType to get column data structures for
 */
type GetColumnDataByType<DT extends MemexColumnDataType> =
  | {
      [ID in SystemColumnId]: GetColumnDataTypeBySystemId<ID> extends DT ? GetColumnDataBySystemId<ID> : never
    }[SystemColumnId]
  | (DT extends CustomColumnKind ? GetColumnDataByCustomColumnDataType<DT> : never)

export type DataTypeToColumnData = {
  [T in MemexColumnDataType]: GetColumnDataByType<T>
}

// ============================================================================
// Title column definitions
// ============================================================================

export type TitleColumnData = GetColumnDataBySystemId<typeof SystemColumnId.Title>

export interface DraftIssueTitleColumnData {
  memexProjectColumnId: typeof SystemColumnId.Title
  value: DraftIssueTitleValue
}

export interface RedactedItemTitleColumnData {
  memexProjectColumnId: typeof SystemColumnId.Title
  value: RedactedItemTitleValue
}

export interface IssueTitleColumnData {
  memexProjectColumnId: typeof SystemColumnId.Title
  value: IssueTitleValue
}

export interface PullRequestTitleColumnData {
  memexProjectColumnId: typeof SystemColumnId.Title
  value: PullRequestTitleValue
}

// ============================================================================
// Column update types
// ============================================================================

export type MakeOptionalIfNotArray<T> = T extends Array<any> ? T : T | undefined

/**
 * ColumnUpdateDataTypeMap defines the type structure for updating column values in the Memex system.
 * This map associates each column data type with its corresponding update payloads.
 * Definitions are only required for updatable column types.
 *
 * Each entry consists of three key components:
 *
 * 1. remoteUpdatePayload - Used to update column values on the server
 *    - Format sent in API requests to the server
 *
 * 2. localUpdatePayload - Used for optimistic updates in the client state
 *    - Format used to immediately update the UI before server response
 *    - NOTE: this closely matches the format of columnData, with the exception that non-array types can be undefined
 *
 * 3. updateColumnValueAction - Emitted from field editors when a user makes a change
 *    - Initial action format when a column value is modified

 * Functions requiring updates when adding or modifying column types:
 * - mapToLocalUpdate(): Must handle transformation from action to local format
 * - mapToRemoteUpdate(): Must handle transformation from action to server format
 *
 * Special cases:
 * - Repository: No remoteUpdatePayload because draft issues must be converted first
 * - Title: Values cannot be null (required field)
 * - TrackedBy: Includes additional 'appendOnly' property
 * - Date: Converts between Date objects and ISO strings
 * - SingleSelect: Can be either system column (Status) or custom column
 *
 * @see mapToLocalUpdate in column-value-payload.ts for client-side transformation
 * @see mapToRemoteUpdate in column-value-payload.ts for server-side transformation
 * @see useUpdateItemColumnValue for how updates are processed and applied
 *
 * For new system columns, use SystemColumnUpdateTemplate
 */

type CustomColumnUpdateTemplate<
  DataType extends CustomColumnKind,
  RemoteValue,
  ColumnValue = GetColumnValueByCustomColumnDataType<DataType>,
> = {
  remoteUpdatePayload: {
    memexProjectColumnId: CustomColumnId
    value: RemoteValue | null
  }
  localUpdatePayload: {
    memexProjectColumnId: CustomColumnId
    value: ColumnValue | undefined
  }
  updateColumnValueAction: {
    dataType: DataType
    value: MakeOptionalIfNotArray<ColumnValue>
    memexProjectColumnId: CustomColumnId
  }
}

type SystemColumnUpdateTemplate<
  Id extends SystemColumnId,
  RemoteValue,
  ColumnDataValue = GetColumnDataBySystemId<Id>['value'],
  ColumnValue = GetColumnValueBySystemId<Id>,
  DataType = GetColumnDataTypeBySystemId<Id>,
> = {
  remoteUpdatePayload: {
    memexProjectColumnId: Id
    value: RemoteValue | null
  }
  localUpdatePayload: {
    memexProjectColumnId: Id
    value: MakeOptionalIfNotArray<ColumnDataValue>
  }
  updateColumnValueAction: {
    dataType: DataType
    value: MakeOptionalIfNotArray<ColumnValue>
  }
}

export type ColumnUpdateDataTypeMap = {
  [MemexColumnDataType.Iteration]: CustomColumnUpdateTemplate<typeof MemexColumnDataType.Iteration, string>
  [MemexColumnDataType.Number]: CustomColumnUpdateTemplate<typeof MemexColumnDataType.Number, number | ''>
  [MemexColumnDataType.Assignees]: SystemColumnUpdateTemplate<typeof SystemColumnId.Assignees, Array<number>>
  [MemexColumnDataType.Labels]: SystemColumnUpdateTemplate<typeof SystemColumnId.Labels, Array<number>>
  [MemexColumnDataType.IssueType]: SystemColumnUpdateTemplate<typeof SystemColumnId.IssueType, IdType>
  [MemexColumnDataType.Milestone]: SystemColumnUpdateTemplate<typeof SystemColumnId.Milestone, IdType>
  [MemexColumnDataType.ParentIssue]: SystemColumnUpdateTemplate<typeof SystemColumnId.ParentIssue, IdType>

  /** Unlike other CustomColumnValues, the value for updateColumnValueAction is a string rather than a local column value */
  [MemexColumnDataType.Text]: {
    remoteUpdatePayload: {
      memexProjectColumnId: CustomColumnId
      value: string | null
    }
    localUpdatePayload: {
      memexProjectColumnId: CustomColumnId
      value: EnrichedText | undefined
    }
    updateColumnValueAction: {
      dataType: typeof MemexColumnDataType.Text
      value: string | undefined // To use SystemColumnUpdateTemplate, this would need to be EnrichedText
      memexProjectColumnId: CustomColumnId
    }
  }

  /** Unlike other CustomColumnValues, the value for updateColumnValueAction does not match the value for localUpdatePayload */
  [MemexColumnDataType.Date]: {
    remoteUpdatePayload: {
      memexProjectColumnId: CustomColumnId
      value: string | null
    }
    localUpdatePayload: {
      memexProjectColumnId: CustomColumnId
      value: ServerDateValue | undefined
    }
    updateColumnValueAction: {
      dataType: typeof MemexColumnDataType.Date
      value: DateValue | undefined // To use SystemColumnUpdateTemplate, this would need to be ServerDateValue
      memexProjectColumnId: CustomColumnId
    }
  }

  /** Unlike other CustomColumnValues, memexProjectColumnId can be custom (number) or system (string) */
  [MemexColumnDataType.SingleSelect]: {
    remoteUpdatePayload: {
      memexProjectColumnId: typeof SystemColumnId.Status | number
      value: string | null
    }
    localUpdatePayload: {
      memexProjectColumnId: typeof SystemColumnId.Status | number
      value: SingleSelectValue | undefined
    }
    updateColumnValueAction: {
      dataType: typeof MemexColumnDataType.SingleSelect
      value: SingleSelectValue | undefined
      memexProjectColumnId: typeof SystemColumnId.Status | number
    }
  }

  /**
   * Unlike other SystemColumnIds, Repository does not have a remoteUpdatePayload.
   * Draft issues must be converted to apply a value, and issues cannot be transferred from within projects.
   */
  [MemexColumnDataType.Repository]: {
    localUpdatePayload: {
      memexProjectColumnId: typeof SystemColumnId.Repository
      value: ExtendedRepository | null
    }
    updateColumnValueAction: {
      dataType: typeof MemexColumnDataType.Repository
      value: ExtendedRepository | undefined
    }
  }

  /**
   * Unlike other SystemColumnIds, Title value cannot be null.
   * Additionally, redacted title values cannot be applied.
   */
  [MemexColumnDataType.Title]: {
    remoteUpdatePayload: {
      memexProjectColumnId: typeof SystemColumnId.Title
      value: {title: string}
    }
    localUpdatePayload: {
      memexProjectColumnId: typeof SystemColumnId.Title
      value: TitleUpdateValue
    }
    updateColumnValueAction: {
      dataType: typeof MemexColumnDataType.Title
      value: TitleUpdateValue
    }
  }
}

// ============================================================================
// Column Update Accessors and Utilities
// ============================================================================

export type UpdatableColumnTypes = keyof ColumnUpdateDataTypeMap
export type UpdateColumnValueAction = ColumnUpdateDataTypeMap[UpdatableColumnTypes]['updateColumnValueAction']
export type LocalUpdatePayload = ColumnUpdateDataTypeMap[UpdatableColumnTypes]['localUpdatePayload']

/**
 * Column data that can be updated directly through the API (excludes repository, which is assigned through conversion of drafts).
 */
export type RemoteUpdateColumnTypes = {
  [K in keyof ColumnUpdateDataTypeMap]: ColumnUpdateDataTypeMap[K] extends {remoteUpdatePayload: any} ? K : never
}[keyof ColumnUpdateDataTypeMap]
export type RemoteUpdatePayload = ColumnUpdateDataTypeMap[RemoteUpdateColumnTypes]['remoteUpdatePayload']

export type GetRemoteUpdateByType<DT extends RemoteUpdateColumnTypes> =
  ColumnUpdateDataTypeMap[DT]['remoteUpdatePayload']

export type MemexItemColumnUpdateData = {
  memexProjectColumnValues: Array<RemoteUpdatePayload>
  layoutType?: string
}

export type ItemUpdates = {
  itemId: number
  updates: Array<UpdateColumnValueAction>
}
