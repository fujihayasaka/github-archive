import {type MemexColumn, MemexColumnDataType} from '../../client/api/columns/contracts/memex-column'
import type {NumericValue} from '../../client/api/columns/contracts/number'
import type {
  DataTypeToColumnData,
  GetRemoteUpdateByType,
  MemexColumnData,
  RemoteUpdateColumnTypes,
  RemoteUpdatePayload,
} from '../../client/api/columns/contracts/storage'
import type {IAssignee, IssueType, Label, Milestone, ParentIssue} from '../../client/api/common-contracts'
import type {MemexItem} from '../../client/api/memex-items/contracts'
import {not_typesafe_nonNullAssertion} from '../../client/helpers/non-null-assertion'
import {MemexRefreshEvents} from '../data/memex-refresh-events'
import type {TrackedByCollection} from '../in-memory-database/tracked-by'

/**
 * A limited interface representing the pieces of the LiveUpdatesController needed by updateColumnValue
 */
interface LiveUpdatesControllerInterface {
  queueSocketMessage: (args: {type: ObjectValues<typeof MemexRefreshEvents>}) => void
}

/**
 * Updates a column value for a memex item based on the column update data send to the `MockServer`
 * Builds an update data action to leverage type guards, and then based on those type guards,
 * calls an appropriate update function to change or add a column value.
 * @param item
 * @param updateData
 * @param columns
 * @param suggestedLabels
 * @param suggestedAssignees
 * @param suggestedMilestones
 */
export function updateColumnValue(
  item: MemexItem,
  updateData: RemoteUpdatePayload,
  columns: Array<MemexColumn>,
  suggestedLabels: Array<Label>,
  suggestedAssignees: Array<IAssignee>,
  suggestedMilestones: Array<Milestone>,
  suggestedIssueTypes: Array<IssueType>,
  parentIssues: Array<ParentIssue>,
  trackedByItems: TrackedByCollection,
  liveUpdateServer: LiveUpdatesControllerInterface,
) {
  const column = columns.find(col => col.id === updateData.memexProjectColumnId)
  if (!column) {
    throw new Error('Column not found')
  }
  const dataType = column.dataType

  let columnValue = item.memexProjectColumnValues.find(
    col => col.memexProjectColumnId === updateData.memexProjectColumnId,
  )
  if (!columnValue) {
    columnValue = {memexProjectColumnId: updateData.memexProjectColumnId} as MemexColumnData
    item.memexProjectColumnValues.push(columnValue)
  }
  try {
    assertRemoteUpdatePayloadKey(dataType)
  } catch {
    // ignore attempts to update non-updatable columns, and return
    return
  }
  const context = {
    suggestedLabels,
    suggestedAssignees,
    suggestedMilestones,
    suggestedIssueTypes,
    parentIssues,
    trackedByItems,
  }

  let result: {shouldDelete: boolean; refreshEvent?: ObjectValues<typeof MemexRefreshEvents>} | undefined

  const handler = getHandler(dataType)

  if (handler) {
    // Cast columnValue to the appropriate type based on dataType
    const typedColumnValue = columnValue as DataTypeToColumnData[typeof dataType]

    result = handler.update(typedColumnValue, updateData, context)

    if (result.refreshEvent) {
      liveUpdateServer.queueSocketMessage({
        type: result.refreshEvent,
      })
      return
    }

    if (result.shouldDelete) {
      const columnValueIndex = item.memexProjectColumnValues.findIndex(
        col => col.memexProjectColumnId === updateData.memexProjectColumnId,
      )
      item.memexProjectColumnValues.splice(columnValueIndex, 1)

      liveUpdateServer.queueSocketMessage({
        type: MemexRefreshEvents.MemexProjectColumnValueDestroy,
      })
    } else {
      liveUpdateServer.queueSocketMessage({
        type: MemexRefreshEvents.MemexProjectColumnValueUpdate,
      })
    }
  }
}

/** Emulate emoji rendering for a subset of the short codes supported on GitHub */
export function renderWithEmoji(input: string): string {
  return input
    .replace(
      ':cat:',
      '<g-emoji class="g-emoji" alias="cat" fallback-src="https://github.githubassets.com/images/icons/emoji/unicode/1f431.png">🐱</g-emoji>',
    )
    .replace(
      ':dog:',
      '<g-emoji class="g-emoji" alias="dog" fallback-src="https://github.githubassets.com/images/icons/emoji/unicode/1f436.png">🐶</g-emoji>',
    )
    .replace(
      ':octocat:',
      '<img class="emoji" title=":octocat:" alt=":octocat:" src="https://github.githubassets.com/images/icons/emoji/octocat.png" height="20" width="20" align="absmiddle">',
    )
    .replace(
      ':shipit:',
      '<img class="emoji" title=":shipit:" alt=":shipit:" src="https://github.githubassets.com/images/icons/emoji/shipit.png" height="20" width="20" align="absmiddle">',
    )
}

// based upon https://davidwells.io/snippets/regex-match-outer-double-quotes
const CodeFenceRegex = /`[^\\`]*(\\`[^\\`]*)*`/g

/** Emulate code block formatting for use in demos and dev environments */
export function formatCodeBlocks(input: string): string {
  let html = input
  let match: RegExpMatchArray | null

  while ((match = CodeFenceRegex.exec(html)) !== null) {
    const item = match[0]
    const index = CodeFenceRegex.lastIndex
    const start = index - item.length

    const newText = `<code>${item.substr(1, item.length - 2)}</code>`
    html = html.substr(0, start) + newText + html.substr(index)
  }

  return html
}

type CustomColumnUpdateHandler<T extends RemoteUpdateColumnTypes> = {
  update: (
    columnData: DataTypeToColumnData[T],
    updateData: GetRemoteUpdateByType<T>,
    context: {
      suggestedLabels: Array<Label>
      suggestedAssignees: Array<IAssignee>
      suggestedMilestones: Array<Milestone>
      suggestedIssueTypes: Array<IssueType>
      parentIssues: Array<ParentIssue>
      trackedByItems: TrackedByCollection
    },
  ) => {
    shouldDelete: boolean
    refreshEvent?: ObjectValues<typeof MemexRefreshEvents>
  }
}

const columnUpdateHandlers: {
  [T in RemoteUpdateColumnTypes]: CustomColumnUpdateHandler<T>
} = {
  [MemexColumnDataType.Text]: {
    update: (columnData, updateData) => {
      if (updateData.value) {
        columnData.value = {
          raw: updateData.value,
          html: renderWithEmoji(updateData.value),
        }
        return {shouldDelete: false}
      }
      return {shouldDelete: true}
    },
  },

  [MemexColumnDataType.Number]: {
    update: (columnData, updateData) => {
      if (updateData.value == null) return {shouldDelete: false}
      if (updateData.value === '') {
        return {shouldDelete: true}
      }
      columnData.value = serverProcessedValueNumber(updateData.value)
      return {shouldDelete: false}
    },
  },

  [MemexColumnDataType.Date]: {
    update: (columnData, updateData) => {
      if (updateData.value == null) return {shouldDelete: false}
      columnData.value = {value: updateData.value}
      return {shouldDelete: false}
    },
  },

  [MemexColumnDataType.SingleSelect]: {
    update: (columnData, updateData) => {
      if (updateData.value == null) return {shouldDelete: false}
      if (updateData.value === undefined) {
        return {shouldDelete: true}
      }
      columnData.value = updateData.value !== '' ? {id: updateData.value} : null
      return {shouldDelete: false}
    },
  },

  [MemexColumnDataType.Iteration]: {
    update: (columnData, updateData) => {
      if (updateData.value == null) return {shouldDelete: false}
      if (updateData.value === undefined) {
        return {shouldDelete: true}
      }
      columnData.value = updateData.value !== '' ? {id: updateData.value} : null
      return {shouldDelete: false}
    },
  },

  [MemexColumnDataType.Title]: {
    update: (columnData, updateData, _context) => {
      const raw = updateData.value?.title ?? columnData.value?.title ?? ''
      if (typeof raw !== 'string') {
        return {shouldDelete: false, refreshEvent: MemexRefreshEvents.MemexProjectColumnValueUpdate}
      }

      if ('number' in columnData.value) {
        columnData.value = {
          ...columnData.value,
          title: {
            raw,
            html: formatCodeBlocks(raw),
          },
        }
      } else {
        // emulate formatting for draft issues
        columnData.value = {
          ...columnData.value,
          title: {
            raw,
            html: renderWithEmoji(raw),
          },
        }
      }

      return {
        shouldDelete: false,
        refreshEvent: MemexRefreshEvents.MemexProjectColumnValueUpdate,
      }
    },
  },

  [MemexColumnDataType.Assignees]: {
    update: (columnData, updateData, {suggestedAssignees}) => {
      if (updateData.value == null) {
        return {shouldDelete: false, refreshEvent: MemexRefreshEvents.IssueUpdateAssignee}
      }

      columnData.value = updateData.value
        .map(id => not_typesafe_nonNullAssertion(suggestedAssignees.find(assignee => assignee.id === id)))
        .sort((a, b) => a.login.localeCompare(b.login))

      return {
        shouldDelete: false,
        refreshEvent: MemexRefreshEvents.IssueUpdateAssignee,
      }
    },
  },

  [MemexColumnDataType.Labels]: {
    update: (columnData, updateData, {suggestedLabels}) => {
      if (updateData.value == null) {
        return {shouldDelete: false, refreshEvent: MemexRefreshEvents.IssueUpdateLabel}
      }

      columnData.value = updateData.value
        .map(id => not_typesafe_nonNullAssertion(suggestedLabels.find(label => label.id === id)))
        .sort((a, b) => a.nameHtml.localeCompare(b.nameHtml))

      return {
        shouldDelete: false,
        refreshEvent: MemexRefreshEvents.IssueUpdateLabel,
      }
    },
  },

  [MemexColumnDataType.Milestone]: {
    update: (columnData, updateData, {suggestedMilestones}) => {
      if (updateData.value === undefined) {
        return {shouldDelete: true}
      }

      columnData.value = not_typesafe_nonNullAssertion(
        suggestedMilestones.find(milestone => milestone.id === updateData.value),
      )

      return {shouldDelete: false}
    },
  },

  [MemexColumnDataType.IssueType]: {
    update: (columnData, updateData, {suggestedIssueTypes}) => {
      if (updateData.value === undefined) {
        return {shouldDelete: true}
      }

      columnData.value = not_typesafe_nonNullAssertion(
        suggestedIssueTypes.find(issueType => issueType.id === updateData.value),
      )

      return {shouldDelete: false}
    },
  },
  [MemexColumnDataType.ParentIssue]: {
    update: (columnData, updateData, {parentIssues}) => {
      if (updateData.value === null) {
        return {shouldDelete: true}
      }

      columnData.value = parentIssues.find(parentIssue => parentIssue.id === updateData.value) || null

      return {shouldDelete: false}
    },
  },
}
function assertRemoteUpdatePayloadKey<T extends MemexColumnDataType>(
  dataType: MemexColumnDataType,
): asserts dataType is T & RemoteUpdateColumnTypes {
  if (!(dataType in columnUpdateHandlers)) {
    throw new Error(`Unsupported data type: ${dataType}`)
  }
}

function getHandler<T extends RemoteUpdateColumnTypes>(dataType: T): CustomColumnUpdateHandler<T> {
  return columnUpdateHandlers[dataType]
}

function serverProcessedValueNumber(value: number): NumericValue {
  return {
    value,
  }
}
