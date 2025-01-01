import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import {ClipboardOnly_UrlColumnModel} from '../constants'
import type {ClipboardColumnBehavior, ClipboardColumnModel} from '../types'
import {behavior as assigneesBehavior} from './assignees'
import {behavior as dateBehavior} from './date'
import {behavior as issueTypeBehavior} from './issue-type'
import {behavior as iterationBehavior} from './iteration'
import {behavior as labelsBehavior} from './labels'
import {behavior as linkedPullRequestsBehavior} from './linked-pull-requests'
import {behavior as milestoneBehavior} from './milestone'
import {behavior as numberBehavior} from './number'
import {behavior as parentIssueBehavior} from './parent-issue'
import {behavior as repositoryBehavior} from './repository'
import {behavior as reviewersBehavior} from './reviewers'
import {behavior as singleSelectBehavior} from './single-select'
import {behavior as subIssuesProgressBehavior} from './sub-issues-progress'
import {behavior as textBehavior} from './text'
import {behavior as titleBehavior} from './title'
import {behavior as trackedByBehavior} from './tracked-by'
import {behavior as tracksBehavior} from './tracks'
import {behavior as urlBehavior} from './url-only'

export type ColumnBehaviorMap = {
  [K in ClipboardColumnModel['dataType']]: ClipboardColumnBehavior<Extract<ClipboardColumnModel, {dataType: K}>>
}

export const behaviors: ColumnBehaviorMap = {
  [MemexColumnDataType.Assignees]: assigneesBehavior,
  [MemexColumnDataType.Date]: dateBehavior,
  [MemexColumnDataType.IssueType]: issueTypeBehavior,
  [MemexColumnDataType.Iteration]: iterationBehavior,
  [MemexColumnDataType.Labels]: labelsBehavior,
  [MemexColumnDataType.LinkedPullRequests]: linkedPullRequestsBehavior,
  [MemexColumnDataType.Milestone]: milestoneBehavior,
  [MemexColumnDataType.Number]: numberBehavior,
  [MemexColumnDataType.ParentIssue]: parentIssueBehavior,
  [MemexColumnDataType.Repository]: repositoryBehavior,
  [MemexColumnDataType.Reviewers]: reviewersBehavior,
  [MemexColumnDataType.SingleSelect]: singleSelectBehavior,
  [MemexColumnDataType.SubIssuesProgress]: subIssuesProgressBehavior,
  [MemexColumnDataType.Text]: textBehavior,
  [MemexColumnDataType.Title]: titleBehavior,
  [MemexColumnDataType.Tracks]: tracksBehavior,
  [MemexColumnDataType.TrackedBy]: trackedByBehavior,
  // URL is a special clipboard column type. When copying a row as plaintext, the project item's URL is included as a separate column.
  [ClipboardOnly_UrlColumnModel.dataType]: urlBehavior,
} as const

export function getBehaviorForColumn(column: ClipboardColumnModel): ClipboardColumnBehavior<any> {
  return behaviors[column.dataType]
}
