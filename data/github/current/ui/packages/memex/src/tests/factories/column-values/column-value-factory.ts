import {Factory} from 'fishery'

import {type MemexColumn, MemexColumnDataType, SystemColumnId} from '../../../client/api/columns/contracts/memex-column'
import type {
  CustomColumnKind,
  CustomColumnMap,
  GetColumnDataByCustomColumnDataType,
  GetColumnDataBySystemId,
  MemexColumnData,
  SystemColumnMap,
} from '../../../client/api/columns/contracts/storage'
import type {Progress} from '../../../client/api/columns/contracts/tracks'
import {
  type ExtendedRepository,
  IssueState,
  type IssueType,
  type LinkedPullRequest,
  type Milestone,
  type ParentIssue,
  PullRequestState,
  type Review,
  type SubIssuesProgress,
} from '../../../client/api/common-contracts'
import type {TrackedByItem} from '../../../client/api/issues-graph/contracts'
import {ItemType} from '../../../client/api/memex-items/item-type'
import {getAllIterationsForConfiguration} from '../../../client/helpers/iterations'
import {isNumber} from '../../../client/helpers/parsing'

class ColumnValueFactory extends Factory<MemexColumnData> {
  private systemColumnValue<ID extends SystemColumnId>(
    columnId: ID,
    value: SystemColumnMap[ID]['columnData']['value'],
  ): GetColumnDataBySystemId<ID> {
    return {
      memexProjectColumnId: columnId,
      value,
    } as GetColumnDataBySystemId<ID>
  }
  private customColumnValue<T extends CustomColumnKind>(
    columnId: number,
    value: CustomColumnMap[T]['columnData']['value'],
  ): GetColumnDataByCustomColumnDataType<T> {
    return {
      memexProjectColumnId: columnId,
      value,
    } as GetColumnDataByCustomColumnDataType<T>
  }
  assignees(assigneeLogins: Array<string>) {
    const assigneesColumnValue = assigneeLogins.map((login, index) => ({
      id: index,
      global_relay_id: 'MDQ6VXN',
      login,
      name: login,
      avatarUrl: 'avatarUrl',
      isSpammy: false,
    }))
    return this.params(this.systemColumnValue(SystemColumnId.Assignees, assigneesColumnValue))
  }

  labels(labelNames: Array<string>) {
    const labelsColumnValue = labelNames.map((name, index) => ({
      id: index,
      name,
      color: 'ffffff',
      nameHtml: name,
      url: 'labelUrl',
    }))
    return this.params(this.systemColumnValue(SystemColumnId.Labels, labelsColumnValue))
  }

  linkedPullRequests(linkedPullRequests: Array<LinkedPullRequest>) {
    return this.params(this.systemColumnValue(SystemColumnId.LinkedPullRequests, linkedPullRequests))
  }

  milestone(milestone: Milestone) {
    return this.params(this.systemColumnValue(SystemColumnId.Milestone, milestone))
  }

  repository(repository: ExtendedRepository) {
    return this.params(this.systemColumnValue(SystemColumnId.Repository, repository))
  }

  status(statusOptionName: string, columns: Array<MemexColumn>) {
    const statusColumn = columns.find(column => column.id === SystemColumnId.Status)
    const option = statusColumn?.settings?.options?.find(o => o.name === statusOptionName)
    if (!option) {
      throw Error(`Please provide a status column with an option with the name ${statusOptionName}`)
    }
    const statusColumnValue = {id: option.id}
    return this.params(this.systemColumnValue(SystemColumnId.Status, statusColumnValue))
  }

  singleSelect(statusOptionName: string, columnName: string, columns: Array<MemexColumn>) {
    const singleSelectColumn = columns.find(
      column => column.name === columnName && column.dataType === MemexColumnDataType.SingleSelect,
    )

    if (!singleSelectColumn) {
      throw Error(`Please provide a single-select column matching the name ${columnName}`)
    }

    const option = singleSelectColumn.settings?.options?.find(o => o.name === statusOptionName)
    if (!option) {
      throw Error(`Please provide a single-select column containing an option matching ${statusOptionName}`)
    }

    if (isNumber(singleSelectColumn.id)) {
      const singleSelectColumnValue = {id: option.id}
      return this.params(this.customColumnValue(singleSelectColumn.id, singleSelectColumnValue))
    } else {
      const statusColumnValue = {id: option.id}
      return this.params(this.systemColumnValue(SystemColumnId.Status, statusColumnValue))
    }
  }

  iteration(iterationTitle: string, columnName: string, columns: Array<MemexColumn>) {
    const iterationColumn = columns.find(
      column => column.name === columnName && column.dataType === MemexColumnDataType.Iteration,
    )

    if (!iterationColumn || !isNumber(iterationColumn.id)) {
      throw Error(`Please provide a iteration field matching the name ${columnName}`)
    }

    if (!iterationColumn.settings?.configuration) {
      throw Error(`No iteration configuration found for column ${columnName}`)
    }

    const allIterations = getAllIterationsForConfiguration(iterationColumn.settings?.configuration)

    const iteration = allIterations.find(o => o.title === iterationTitle)
    if (!iteration) {
      throw Error(`Please provide an iteration field with a title matching ${iterationTitle}`)
    }

    const iterationColumnValue = {id: iteration.id}
    return this.params(this.customColumnValue(iterationColumn.id, iterationColumnValue))
  }

  reviewers(reviewers: Array<Review>) {
    return this.params(this.systemColumnValue(SystemColumnId.Reviewers, reviewers))
  }

  tracks(progress: Progress) {
    return this.params(this.systemColumnValue(SystemColumnId.Tracks, progress))
  }

  parentIssue(parentIssue: ParentIssue) {
    return this.params(this.systemColumnValue(SystemColumnId.ParentIssue, parentIssue))
  }

  subIssuesProgress(progress: SubIssuesProgress) {
    return this.params(this.systemColumnValue(SystemColumnId.SubIssuesProgress, progress))
  }

  trackedBy(trackedByItems: Array<TrackedByItem>) {
    return this.params(this.systemColumnValue(SystemColumnId.TrackedBy, trackedByItems))
  }

  issueType(issueType: IssueType) {
    return this.params(this.systemColumnValue(SystemColumnId.IssueType, issueType))
  }

  title(title: string, itemType: ItemType) {
    switch (itemType) {
      case ItemType.DraftIssue: {
        const titleColumnValue = {title: {raw: title, html: title}}
        return this.params(this.systemColumnValue(SystemColumnId.Title, titleColumnValue))
      }
      case ItemType.Issue: {
        const titleColumnValue = {title: {raw: title, html: title}, number: 1234, issueId: 123, state: IssueState.Open}
        return this.params(this.systemColumnValue(SystemColumnId.Title, titleColumnValue))
      }
      case ItemType.PullRequest: {
        const titleColumnValue = {
          title: {raw: title, html: title},
          number: 1234,
          issueId: 123,
          isDraft: false,
          state: PullRequestState.Open,
        }
        return this.params(this.systemColumnValue(SystemColumnId.Title, titleColumnValue))
      }
      case ItemType.RedactedItem: {
        const titleColumnValue = {
          title: "You don't have permission to access this item",
        }
        return this.params(this.systemColumnValue(SystemColumnId.Title, titleColumnValue))
      }
    }
  }

  text(value: string, columnName: string, columns: Array<MemexColumn>) {
    const column = columns.find(c => c.name === columnName)
    if (!column) {
      throw new Error(
        `Could not find column with name '${columnName}' among the provided columns: ${columns
          .map(c => c.name)
          .join(', ')}`,
      )
    }
    if (column.dataType !== 'text') {
      throw new Error(`Expected '${columnName}' column to have number type, but got '${column.dataType}' instead`)
    }

    const textColumnValue = {raw: value, html: value}
    return this.params(this.customColumnValue(column.databaseId, textColumnValue))
  }

  number(value: number, columnName: string, columns: Array<MemexColumn>) {
    const column = columns.find(c => c.name === columnName)
    if (!column) {
      throw new Error(
        `Could not find column with name '${columnName}' among the provided columns: ${columns
          .map(c => c.name)
          .join(', ')}`,
      )
    }
    if (column.dataType !== 'number') {
      throw new Error(`Expected '${columnName}' column to have number type, but got '${column.dataType}' instead`)
    }
    const numberColumnValue = {value}
    return this.params(this.customColumnValue(column.databaseId, numberColumnValue))
  }

  date(value: string, columnName: string, columns: Array<MemexColumn>) {
    const column = columns.find(c => c.name === columnName)
    if (!column) {
      throw new Error(
        `Could not find column with name '${columnName}' among the provided columns: ${columns
          .map(c => c.name)
          .join(', ')}`,
      )
    }
    if (column.dataType !== 'date') {
      throw new Error(`Expected '${columnName}' column to have date type, but got '${column.dataType}' instead`)
    }
    const dateColumnValue = {value}
    return this.params(this.customColumnValue(column.databaseId, dateColumnValue))
  }
}

export const columnValueFactory = ColumnValueFactory.define(() => {
  return {
    memexProjectColumnId: SystemColumnId.Assignees,
    value: null,
  }
})
