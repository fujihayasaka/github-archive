import type {BetterSystemStyleObject} from '@primer/react'

import {MemexColumnDataType} from '../../../../api/columns/contracts/memex-column'
import type {FieldGrouping} from '../../../../features/grouping/types'
import {assertNever} from '../../../../helpers/assert-never'
import {formatDateString, formatISODateString} from '../../../../helpers/parsing'
import {columnUsesDefaultHeader, resolveTitleForDefaultHeader} from '../../../../helpers/table-group-utilities'
import {isToday} from '../../../../helpers/util'
import type {FieldAggregate} from '../../../../hooks/use-aggregation-settings'
import {AssigneesGroupHeaderLabel} from './assignees-group-header-label'
import {DefaultGroupHeaderLabel} from './default-group-header-label'
import {IterationGroupHeaderLabel} from './iteration-group-header-label'
import {ParentIssueGroupHeaderLabel} from './parent-issue-group-header-label'
import {RepositoryGroupHeaderLabel} from './repository-group-header-label'
import {SingleSelectGroupHeaderLabel} from './single-select-group-header-label'

type GroupHeaderLabelProps = {
  sourceObject: FieldGrouping
  rowCount: number
  aggregates: Array<FieldAggregate>
  hideItemsCount: boolean
  titleSx?: BetterSystemStyleObject
}

export const GroupHeaderLabel = ({
  sourceObject,
  rowCount,
  aggregates,
  hideItemsCount,
  titleSx,
}: GroupHeaderLabelProps) => {
  if (sourceObject.kind === 'empty') {
    return (
      <DefaultGroupHeaderLabel
        titleHtml={sourceObject.value.titleHtml}
        rowCount={rowCount}
        aggregates={aggregates}
        hideItemsCount={hideItemsCount}
        titleSx={titleSx}
      />
    )
  }

  if (columnUsesDefaultHeader(sourceObject)) {
    const titleHtml = resolveTitleForDefaultHeader(sourceObject)

    return (
      <DefaultGroupHeaderLabel
        titleHtml={titleHtml}
        rowCount={rowCount}
        aggregates={aggregates}
        hideItemsCount={hideItemsCount}
        titleSx={titleSx}
      />
    )
  }

  switch (sourceObject.dataType) {
    case MemexColumnDataType.Assignees:
      return (
        <AssigneesGroupHeaderLabel
          assignees={sourceObject.value}
          rowCount={rowCount}
          aggregates={aggregates}
          hideItemsCount={hideItemsCount}
          titleSx={titleSx}
        />
      )
    case MemexColumnDataType.Date: {
      const titleHtml = formatDateString(sourceObject.value.date.value)
      const value = formatISODateString(sourceObject.value.date.value)
      const label = isToday(value) ? 'Today' : undefined
      return (
        <DefaultGroupHeaderLabel
          titleHtml={titleHtml}
          label={label}
          rowCount={rowCount}
          aggregates={aggregates}
          hideItemsCount={hideItemsCount}
          titleSx={titleSx}
        />
      )
    }
    case MemexColumnDataType.Repository:
      return (
        <RepositoryGroupHeaderLabel
          repository={sourceObject.value}
          rowCount={rowCount}
          aggregates={aggregates}
          hideItemsCount={hideItemsCount}
          titleSx={titleSx}
        />
      )
    case MemexColumnDataType.Iteration:
      return (
        <IterationGroupHeaderLabel
          iteration={sourceObject.value.iteration}
          rowCount={rowCount}
          aggregates={aggregates}
          hideItemsCount={hideItemsCount}
          titleSx={titleSx}
        />
      )
    case MemexColumnDataType.ParentIssue:
      return (
        <ParentIssueGroupHeaderLabel
          parentIssue={sourceObject.value}
          aggregates={aggregates}
          hideItemsCount={hideItemsCount}
          rowCount={rowCount}
          titleSx={titleSx}
        />
      )
    case MemexColumnDataType.SingleSelect:
      return (
        <SingleSelectGroupHeaderLabel
          option={sourceObject.value.option}
          rowCount={rowCount}
          aggregates={aggregates}
          hideItemsCount={hideItemsCount}
          titleSx={titleSx}
        />
      )

    default: {
      assertNever(sourceObject)
    }
  }
}
