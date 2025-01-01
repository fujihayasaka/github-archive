import {GitHubAvatar} from '@github-ui/github-avatar'
import type {ColorName} from '@github-ui/use-named-color'
import {Box, Truncate} from '@primer/react'
import {useCallback} from 'react'

import type {ServerDateValue} from '../api/columns/contracts/date'
import type {IterationValue} from '../api/columns/contracts/iteration'
import {MemexColumnDataType, type SystemColumnId} from '../api/columns/contracts/memex-column'
import type {NumericValue} from '../api/columns/contracts/number'
import type {ColumnData} from '../api/columns/contracts/storage'
import type {EnrichedText} from '../api/columns/contracts/text'
import type {IAssignee, Review, User} from '../api/common-contracts'
import {ItemType} from '../api/memex-items/item-type'
import type {IssueType, Label, Milestone} from '../components/automation/fragments/search-input'
import {SanitizedHtml} from '../components/dom/sanitized-html'
import {RepositoryIcon} from '../components/fields/repository/repository-icon'
import {ColorDecorator} from '../components/fields/single-select/color-decorator'
import {MeToken, TodayToken} from '../components/filter-bar/helpers/search-constants'
import {ItemState} from '../components/item-state'
import {getInitialState} from '../helpers/initial-state'
import {getAllIterations, IterationToken} from '../helpers/iterations'
import {formatDateString, formatISODateString, parseDateValue, parseTitleDefaultRaw} from '../helpers/parsing'
import {fullDisplayName} from '../helpers/tracked-by-formatter'
import type {ColumnModel} from '../models/column-model'
import {isDateColumnModel} from '../models/column-model/guards'
import type {MemexItemModel} from '../models/memex-item-model'
import styles from './use-search-filter-suggestions.module.css'

export type RepoSuggestions = {
  labels?: ReadonlyArray<Label>
  milestones?: ReadonlyArray<Milestone>
  issueTypes?: ReadonlyArray<IssueType>
}

/**
 * Priorities are relative to each-other, and
 * used for the default sorting mechanism.
 * User generated values are always compared using
 * a priority of 0, falling back to comparisons of their values
 *
 * When compared, higher values appear _first_ and lower values appear later
 */
export const SuggestionsPriority = {
  UserDefined: 0,
  SystemExclude: 1,
  SystemNo: 2,
  SystemHas: 3,
  Me: 4,
  PreviousIteration: 5, // bottom most iteration suggestion
  NextIteration: 6,
  CurrentIteration: 7, // top most iteration suggestion
  TodayToken: 7, // same as current iteration
} as const
export type SuggestionsPriority = ObjectValues<typeof SuggestionsPriority>
/**
 * This type is a container to allow us to attach metadata to the values
 * generated for viewing in the search suggestions
 */
type ColumnValue = {
  /**
   * This key is used to control how and where an element is rendered when shown in
   * suggestions:
   *
   *  - `priority` is used to render the item with accent in
   *    the suggestion list (current iteration, @me) and to position them
   *    in the suggestion list in front of the default values; suggested so start assigning
   *    priority starting with 2 (above default values and system values)
   *  - priority 1 is used for system filter suggestion (e.g. exclude & empty filters)
   *  - 0 | undefined priority is the default value and reverts to the default rendering
   */
  priority?: SuggestionsPriority
  /**
   * This is the underlying value which should be used when populating the
   * search filter.
   */
  value: string
  /**
   * Optional render function for ui-rich suggestions
   */
  renderItem?: () => JSX.Element
}
type ColumnValuesMap = Map<string, ColumnValue>

/**
 * Returns all the unique values of a column in the memex,
 * as a map sorted alphabetically unless the column is single select in which case they are in option order.
 * The type of the column determines which value is returned.
 *
 * @param items - Array of project items to inspect
 *
 * @param labels - Array of label column values to show
 *
 * @returns Callback to invoke to resolve suggestions based on current filter state
 */

export function useSearchFilterSuggestions(
  items: ReadonlyArray<MemexItemModel>,
  repoSuggestions?: RepoSuggestions,
  issueTypeSuggestedNames?: ReadonlyArray<string>,
) {
  const getSuggestionsForColumn = useCallback(
    (column: ColumnModel, currentFilterValue: string, qualifierValue: string, isNegativeFilterActive: boolean) => {
      const databaseId = column.databaseId

      const uniqueColumnValues = getSuggestableColumnsWithValues(
        items,
        column,
        repoSuggestions,
        issueTypeSuggestedNames,
      )

      // Empty and exclude currently do not work as part of an existing comma-separated column filter
      // Hide suggestions for now, in favor of eventual overall improvements to filtering syntax parsing
      // https://github.com/github/planning-tracking/issues/984
      if (!currentFilterValue) {
        if (!isNegativeFilterActive) {
          uniqueColumnValues.set(`exclude-${databaseId}`, {
            value: `exclude-${databaseId}`,
            priority: SuggestionsPriority.SystemExclude,
          })
        }
        // Always add empty and present values filter menu options to the top of the list
        uniqueColumnValues.set(`present-${databaseId}`, {
          value: `present-${databaseId}`,
          priority: SuggestionsPriority.SystemHas,
        })

        uniqueColumnValues.set(`empty-${databaseId}`, {
          value: `empty-${databaseId}`,
          priority: SuggestionsPriority.SystemNo,
        })
      }

      const suggestibleKeys = Array.from(uniqueColumnValues.keys())

      // sort items on their priority
      suggestibleKeys.sort(
        (a, b) =>
          (uniqueColumnValues.get(b)?.priority ?? SuggestionsPriority.UserDefined) -
          (uniqueColumnValues.get(a)?.priority ?? SuggestionsPriority.UserDefined),
      )

      const filteredKeys = suggestibleKeys.filter(key => {
        if (typeof key !== 'string') {
          return false
        }

        // For date columns, check if the user is typing `2021-11-22` or `Nov 22`
        // For tracked by columns, check if the user is typing `org/repo#number` or issue title
        if (
          isDateColumnModel(column) ||
          column.dataType === MemexColumnDataType.TrackedBy ||
          column.dataType === MemexColumnDataType.ParentIssue
        ) {
          if (key.toLowerCase().includes(qualifierValue)) {
            return true
          }

          const result = uniqueColumnValues.get(key)
          const isUserDefinedValue =
            result && (result.priority ?? SuggestionsPriority.UserDefined) === SuggestionsPriority.UserDefined

          if (isUserDefinedValue) {
            return result.value.toLowerCase().includes(qualifierValue)
          }
        }

        if (currentFilterValue.includes(key)) {
          return false
        }
        return key.toLowerCase().includes(qualifierValue)
      })

      // If there's only 1 suggestion and it is already in the query string, then don't show it.
      if (filteredKeys.length === 1 && filteredKeys[0]?.toLowerCase() === qualifierValue) {
        filteredKeys.pop()
      }

      return {filteredKeys, uniqueColumnValues}
    },
    [items, repoSuggestions, issueTypeSuggestedNames],
  )

  return {
    getSuggestionsForColumn,
  }
}

function sortMapByPriorityAndValueString(map: Map<string, ColumnValue>) {
  return new Map(
    [...map.entries()].sort((a, b) => {
      const priorityA = a[1].priority ?? 0
      const priorityB = b[1].priority ?? 0
      const comparedPriority = priorityB - priorityA
      if (comparedPriority !== 0) {
        return comparedPriority
      }
      const keyA = a[0]
      const keyB = b[0]
      return keyA.localeCompare(keyB)
    }),
  )
}

function processColumnValueForEachItem<T>(
  column: ColumnModel,
  items: Readonly<Array<MemexItemModel>>,
  cb: (columnData: NonNullable<T>) => void,
) {
  for (const item of items) {
    const columnData = item.columns
    if (!columnData[column.id]) continue
    const data = columnData[column.id] as T
    if (!data) continue
    cb(data)
  }
}

const SingleSelectSuggestion = ({color, nameHtml}: {color: ColorName; nameHtml: string}) => (
  <div className={styles.Box}>
    <ColorDecorator color={color} className={styles.ColorDecorator} />
    <SanitizedHtml>{nameHtml}</SanitizedHtml>
  </div>
)

const LabelSuggestion = ({color, nameHtml}: {color: string; nameHtml: string}) => (
  <div className={styles.Box}>
    <Box
      sx={{
        bg: `#${color}`,
        borderColor: `#${color}`,
      }}
      className={styles.Box_1}
    />
    <SanitizedHtml>{nameHtml}</SanitizedHtml>
  </div>
)

export function getSuggestableColumnsWithValues(
  items: Readonly<Array<MemexItemModel>>,
  column: ColumnModel | undefined,
  repoSuggestions?: RepoSuggestions,
  issueTypeSuggestedNames?: ReadonlyArray<string>,
): ColumnValuesMap {
  const {loggedInUser} = getInitialState()
  const uniqueColumnValues = new Map<string, ColumnValue>()
  if (!column) return uniqueColumnValues

  switch (column.dataType) {
    /**
     * Column suggestions using custom sorting
     */
    case MemexColumnDataType.SingleSelect: {
      for (const option of column.settings.options ?? []) {
        uniqueColumnValues.set(option.name, {
          value: option.nameHtml,
          renderItem: () => <SingleSelectSuggestion color={option.color} nameHtml={option.nameHtml} />,
        })
      }

      // single select options are sorted by the defined options order
      return uniqueColumnValues
    }
    case MemexColumnDataType.Number: {
      const values = new Set<number>()
      processColumnValueForEachItem<NumericValue>(column, items, data => {
        values.add(data.value)
      })

      for (const value of [...values].sort((a, b) => a - b)) {
        uniqueColumnValues.set(`${value}`, {value: `${value}`})
      }

      // number suggestions are sorted by their numeric value
      return uniqueColumnValues
    }
    /**
     * Column suggestions using default `sortMapByPriorityAndValueString` sorting
     */
    case MemexColumnDataType.Iteration: {
      uniqueColumnValues.set(IterationToken.Current, {
        value: IterationToken.Current,
        priority: SuggestionsPriority.CurrentIteration,
      })

      uniqueColumnValues.set(IterationToken.Next, {
        value: IterationToken.Next,
        priority: SuggestionsPriority.NextIteration,
      })

      uniqueColumnValues.set(IterationToken.Previous, {
        value: IterationToken.Previous,
        priority: SuggestionsPriority.PreviousIteration,
      })

      const iterationIds = new Set<string>()
      processColumnValueForEachItem<IterationValue>(column, items, iteration => {
        iterationIds.add(iteration.id)
      })

      for (const iteration of getAllIterations(column)) {
        const iterationIdExists = iterationIds.has(iteration.id)

        if (iterationIdExists) {
          uniqueColumnValues.set(iteration.title, {value: iteration.titleHtml})
        }
      }
      break
    }
    case MemexColumnDataType.TrackedBy: {
      processColumnValueForEachItem<ColumnData[typeof SystemColumnId.TrackedBy]>(column, items, parentItems => {
        for (const parentItem of parentItems) {
          const key = fullDisplayName(parentItem)
          uniqueColumnValues.set(key, {
            value: parentItem.title,
            renderItem: () => (
              <div className={styles.Box_2}>
                <ItemState state={parentItem.state} type={'Issue'} isDraft={false} isBlocked={false} />
                <Truncate title={parentItem.title} className={styles.Truncate}>
                  {parentItem.title}
                </Truncate>
                <span className={styles.Text}>{key}</span>
              </div>
            ),
          })
        }
      })
      break
    }
    case MemexColumnDataType.Assignees: {
      processColumnValueForEachItem<ColumnData[typeof SystemColumnId.Assignees]>(column, items, assignees => {
        updateUniqueColumnValuesForUserField(uniqueColumnValues, loggedInUser, assignees)
      })
      break
    }
    case MemexColumnDataType.Labels: {
      if (repoSuggestions?.labels) {
        for (const label of repoSuggestions.labels) {
          uniqueColumnValues.set(label.name, {
            value: label.nameHTML,
            renderItem: () => <LabelSuggestion nameHtml={label.nameHTML} color={label.color} />,
          })
        }
      } else {
        processColumnValueForEachItem<ColumnData[typeof SystemColumnId.Labels]>(column, items, labels => {
          for (const label of labels) {
            uniqueColumnValues.set(label.name, {
              value: label.nameHtml,
              renderItem: () => <LabelSuggestion nameHtml={label.nameHtml} color={label.color} />,
            })
          }
        })
      }

      break
    }
    case MemexColumnDataType.LinkedPullRequests: {
      processColumnValueForEachItem<ColumnData[typeof SystemColumnId.LinkedPullRequests]>(
        column,
        items,
        linkedPullRequests => {
          for (const val of linkedPullRequests) {
            uniqueColumnValues.set(val.number.toString(), {
              value: val.number.toString(),
              renderItem: () => (
                <div className={styles.Box_3}>
                  <ItemState isDraft={val.isDraft} state={val.state} type={ItemType.PullRequest} isBlocked={false} />
                  <span className={styles.Text_1}>{`#${val.number}`}</span>
                </div>
              ),
            })
          }
        },
      )

      break
    }
    case MemexColumnDataType.Repository: {
      processColumnValueForEachItem<ColumnData[typeof SystemColumnId.Repository]>(column, items, repository => {
        uniqueColumnValues.set(repository.nameWithOwner, {
          value: repository.nameWithOwner,
          renderItem: () => (
            <div className={styles.Box_3}>
              <RepositoryIcon repository={repository} />
              <span className={styles.Text_1}>{repository.nameWithOwner}</span>
            </div>
          ),
        })
      })
      break
    }
    case MemexColumnDataType.Reviewers: {
      processColumnValueForEachItem<ColumnData[typeof SystemColumnId.Reviewers]>(column, items, reviewers => {
        updateUniqueColumnValuesForUserField(uniqueColumnValues, loggedInUser, reviewers)
      })
      break
    }
    case MemexColumnDataType.Milestone: {
      if (repoSuggestions?.milestones) {
        for (const milestone of repoSuggestions.milestones) {
          uniqueColumnValues.set(milestone.title, {value: milestone.title})
        }
      } else {
        processColumnValueForEachItem<ColumnData[typeof SystemColumnId.Milestone]>(column, items, value => {
          uniqueColumnValues.set(value.title, {value: value.title})
        })
      }
      break
    }
    case MemexColumnDataType.IssueType: {
      if (repoSuggestions?.issueTypes) {
        for (const issueType of repoSuggestions.issueTypes) {
          uniqueColumnValues.set(issueType.name, {value: issueType.name})
        }
      } else if (issueTypeSuggestedNames) {
        for (const name of issueTypeSuggestedNames) {
          uniqueColumnValues.set(name, {value: name})
        }
      } else {
        processColumnValueForEachItem<ColumnData[typeof SystemColumnId.IssueType]>(column, items, value => {
          uniqueColumnValues.set(value.name, {value: value.name})
        })
      }
      break
    }
    case MemexColumnDataType.ParentIssue: {
      processColumnValueForEachItem<ColumnData[typeof SystemColumnId.ParentIssue]>(column, items, parent => {
        uniqueColumnValues.set(parent.nwoReference, {
          value: parent.title,
          renderItem: () => (
            <div className={styles.Box_2}>
              <ItemState
                state={parent.state}
                stateReason={parent.stateReason}
                type={'Issue'}
                isDraft={false}
                isBlocked={false}
              />
              <Truncate title={parent.title} className={styles.Truncate_1}>
                {parent.title}
              </Truncate>
              <span className={styles.Text_2}>{parent.nwoReference}</span>
            </div>
          ),
        })
      })
      break
    }
    case MemexColumnDataType.SubIssuesProgress: {
      break
    }
    case MemexColumnDataType.Title: {
      processColumnValueForEachItem<ColumnData[typeof SystemColumnId.Title]>(column, items, titleValue => {
        const title = parseTitleDefaultRaw(titleValue)
        uniqueColumnValues.set(title, {value: title})
      })

      break
    }
    case MemexColumnDataType.Text: {
      processColumnValueForEachItem<EnrichedText>(column, items, value => {
        uniqueColumnValues.set(value.raw, {value: value.html})
      })
      break
    }
    case MemexColumnDataType.Date: {
      uniqueColumnValues.set(TodayToken, {value: TodayToken, priority: SuggestionsPriority.TodayToken})
      processColumnValueForEachItem<ServerDateValue>(column, items, value => {
        const dateValue = parseDateValue(value)
        if (dateValue) {
          const dateISO = formatISODateString(dateValue.value)
          const dateString = formatDateString(dateValue.value)
          if (dateISO && dateString) {
            uniqueColumnValues.set(dateISO, {value: dateString})
          }
        }
      })
      break
    }
  }

  return sortMapByPriorityAndValueString(uniqueColumnValues)
}

/**
 * Encapsulates the logic around forming the filter suggestions list for a column
 * containing "user" types. Will include @me as a suggestion if the user is logged in.
 * @param uniqueColumnValues map to update with suggestions
 * @param loggedInUser the currently logged in user (if any)
 * @param users the user data to use for suggestions
 */
function updateUniqueColumnValuesForUserField(
  uniqueColumnValues: Map<string, ColumnValue>,
  loggedInUser: Pick<User, 'id' | 'login'> | undefined,
  users: Array<Review> | Array<IAssignee>,
) {
  if (loggedInUser?.login) {
    uniqueColumnValues.set(MeToken, {value: MeToken, priority: SuggestionsPriority.Me})
  }
  for (const user of users) {
    const value = 'reviewer' in user ? user.reviewer.name : user.login
    const avatarUrl = 'reviewer' in user ? user.reviewer.avatarUrl : user.avatarUrl

    uniqueColumnValues.set(value, {
      value,
      renderItem: () => (
        <div className={styles.Box_3}>
          {/* NOTE: This image has empty alt text, because the value is already displayed in the text, so the image is purely decorative */}
          <GitHubAvatar loading="lazy" alt="" src={avatarUrl} className={styles.GitHubAvatar} />
          <span>{value}</span>
        </div>
      ),
    })
  }
}
