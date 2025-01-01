import {GitHubAvatar} from '@github-ui/github-avatar'
import {usePortalTooltip} from '@github-ui/portal-tooltip/use-portal-tooltip'
import {testIdProps} from '@github-ui/test-id-props'
import {IterationsIcon, MilestoneIcon} from '@primer/octicons-react'
import {ActionList, Button, CounterLabel, Heading, Label, Link, Stack} from '@primer/react'
import {clsx} from 'clsx'
import {useDeferredValue, useEffect, useRef} from 'react'

import {partition} from '../../../utils/partition'
import type {Iteration} from '../../api/columns/contracts/iteration'
import {MemexColumnDataType} from '../../api/columns/contracts/memex-column'
import {ItemType} from '../../api/memex-items/item-type'
import {SlicerPanelUI} from '../../api/stats/contracts'
import {useFilteredItems} from '../../features/filtering/hooks/use-filtered-items'
import type {EmptyCustomGroup, IterationGrouping} from '../../features/grouping/types'
import {NO_SLICE_VALUE, type SliceValue} from '../../features/slicing/hooks/use-slice-by'
import {useOpenParentIssue} from '../../features/sub-issues/use-open-parent-issue'
import {intervalDatesDescription, isCurrentIteration, partitionAllIterations} from '../../helpers/iterations'
import {formatDateString, formatISODateString} from '../../helpers/parsing'
import {sanitizeTextInputHtmlString} from '../../helpers/sanitize'
import {isToday} from '../../helpers/util'
import {useEnabledFeatures} from '../../hooks/use-enabled-features'
import type {IssueModel, MemexItemModel} from '../../models/memex-item-model'
import {useTrackedByItemsContext} from '../../state-providers/tracked-by-items/use-tracked-by-items-context'
import {Resources, TrackedByResources} from '../../strings'
import {SanitizedHtml} from '../dom/sanitized-html'
import {CurrentIterationLabel} from '../fields/iteration/iteration-label'
import {LabelDecorator} from '../fields/label-token'
import {RepositoryIcon} from '../fields/repository/repository-icon'
import {ColorDecorator} from '../fields/single-select/color-decorator'
import {SubIssuesProgressBar} from '../fields/sub-issues-progress-bar'
import {TracksToken} from '../fields/tracks/tracks-token'
import {ProjectInputWithSearchContext} from '../filter-bar/base-project-view-filter-input'
import {ItemState, ItemStateForTitle} from '../item-state'
import {TrackedByMissingIssuesButton} from '../tracked-by/tracked-by-missing-issues-button'
import styles from './slicer-items.module.css'
import type {SlicerItemGroup} from './slicer-items-provider'

const fieldsWithNoLeadingIcon = new Set<MemexColumnDataType>([
  MemexColumnDataType.Text,
  MemexColumnDataType.Number,
  MemexColumnDataType.Date,
  MemexColumnDataType.IssueType,
])

const ListItemCountMetadata = ({count}: {count: number}) => (
  <div className={styles.trailingVisual}>
    <CounterLabel {...testIdProps('slicer-item-count')}>{count}</CounterLabel>
  </div>
)

const ListContainer = ({children, hasLeadingIcons = true}: {children: React.ReactNode; hasLeadingIcons?: boolean}) => (
  <div className={clsx(styles.listContainerBase, hasLeadingIcons ? styles.withIcons : styles.noIcons)}>{children}</div>
)

type SlicerItemCommonProps = {
  sliceValue: SliceValue
  onSliceValueChange: (value: SliceValue) => void
}

type SlicerItemGroupedProps = SlicerItemCommonProps & {
  count: number
}

/* Iteration */

const SlicerIterationItem = ({
  fieldGrouping,
  count,
  onSliceValueChange,
  sliceValue,
}: SlicerItemGroupedProps & {
  fieldGrouping: Exclude<IterationGrouping, EmptyCustomGroup>
}) => {
  return (
    <StandardSlicerItem
      onSelect={() => onSliceValueChange(fieldGrouping.value.iteration.title)}
      isActive={sliceValue === fieldGrouping.value.iteration.title}
      icon={<IterationsIcon className="fgColor-muted" />}
      title={fieldGrouping.value.iteration.titleHtml}
      description={<div className={styles.description}>{intervalDatesDescription(fieldGrouping.value.iteration)}</div>}
      metadata={
        <>
          {isCurrentIteration(new Date(), fieldGrouping.value.iteration) && (
            <div>
              <CurrentIterationLabel sx={{ml: 2}} />
            </div>
          )}
          <ListItemCountMetadata count={count} />
        </>
      }
    />
  )
}

const StandardSlicerItem = ({
  onSelect,
  isActive,
  icon,
  title,
  description,
  metadata,
  trailingContent,
  wrapTrailingContent = false,
}: {
  onSelect: () => void
  isActive: boolean
  icon?: JSX.Element
  title: JSX.Element | string
  description?: JSX.Element
  metadata?: JSX.Element
  trailingContent?: JSX.Element
  wrapTrailingContent?: boolean
}) => {
  const titleContent =
    typeof title === 'string' ? (
      <SanitizedHtml as="h3" className={styles.title}>
        {title}
      </SanitizedHtml>
    ) : (
      title
    )
  return (
    <ActionList.Item
      onSelect={onSelect}
      className={clsx(isActive && styles.actionListItemActive, styles.actionListItem, 'active-item')}
    >
      <div className={styles.actionListItemContainer}>
        <div className={clsx(styles.leadingVisual, styles.leadingContent)}>
          <div className={styles.icon}>{icon}</div>
        </div>
        <div className={styles.mainContent}>
          <div className="flex-1 pr-2 py-2 text-left">
            {titleContent}
            {description}
            {wrapTrailingContent && <div className={styles.itemFullWidth}>{trailingContent}</div>}
          </div>
          {metadata}
        </div>
        {trailingContent && (
          <div className={clsx(wrapTrailingContent && styles.itemRight, styles.trailingContent)}>{trailingContent}</div>
        )}
      </div>
    </ActionList.Item>
  )
}

const getSlicerItem = ({
  group,
  onSliceValueChange,
  sliceValue,
}: {
  group: SlicerItemGroup
  sliceValue: SliceValue
  onSliceValueChange: (value: SliceValue) => void
}) => {
  const count = group.totalCount.value

  if (group.sourceObject.kind === 'empty') {
    const fieldGrouping = group.sourceObject
    return (
      <StandardSlicerItem
        key={NO_SLICE_VALUE}
        isActive={sliceValue === NO_SLICE_VALUE}
        title={fieldGrouping.value.titleHtml}
        onSelect={() => onSliceValueChange(NO_SLICE_VALUE)}
        metadata={<ListItemCountMetadata count={count} />}
      />
    )
  }

  switch (group.sourceObject.dataType) {
    case MemexColumnDataType.SingleSelect: {
      const fieldGrouping = group.sourceObject
      const value = fieldGrouping.value.option.name
      return (
        <StandardSlicerItem
          key={fieldGrouping.value.option.id}
          isActive={sliceValue === value}
          onSelect={() => onSliceValueChange(value)}
          title={fieldGrouping.value.option.nameHtml}
          icon={<ColorDecorator color={fieldGrouping.value.option.color} />}
          description={
            fieldGrouping.value.option.descriptionHtml ? (
              <div className={styles.description}>
                <SanitizedHtml>{fieldGrouping.value.option.descriptionHtml}</SanitizedHtml>
              </div>
            ) : undefined
          }
          metadata={<ListItemCountMetadata count={count} />}
        />
      )
    }
    case MemexColumnDataType.Assignees: {
      const assignee = group.sourceObject.value[0]
      if (!assignee) return null

      return (
        <StandardSlicerItem
          key={assignee.id}
          onSelect={() => onSliceValueChange(assignee.login)}
          isActive={sliceValue === assignee.login}
          icon={<GitHubAvatar loading="lazy" key={assignee.id} alt={assignee.login} src={assignee.avatarUrl} />}
          title={assignee.login}
          metadata={<ListItemCountMetadata count={count} />}
        />
      )
    }
    case MemexColumnDataType.Labels: {
      const fieldGrouping = group.sourceObject
      const value = fieldGrouping.value.name
      return (
        <StandardSlicerItem
          key={fieldGrouping.value.id}
          isActive={sliceValue === value}
          onSelect={() => onSliceValueChange(value)}
          icon={<LabelDecorator color={fieldGrouping.value.color} />}
          title={fieldGrouping.value.nameHtml}
          metadata={<ListItemCountMetadata count={count} />}
        />
      )
    }
    case MemexColumnDataType.Milestone: {
      const fieldGrouping = group.sourceObject
      const value = fieldGrouping.value.title
      return (
        <StandardSlicerItem
          key={fieldGrouping.value.id}
          isActive={sliceValue === value}
          onSelect={() => onSliceValueChange(value)}
          icon={<MilestoneIcon className="fgColor-muted" />}
          title={value}
          metadata={<ListItemCountMetadata count={count} />}
        />
      )
    }
    case MemexColumnDataType.ParentIssue: {
      const parentIssue = group.sourceObject.value

      const ParentIssueTitleText: React.FC = () => {
        return (
          <>
            <SanitizedHtml as="h3" className={styles.parentIssueTitle}>
              {parentIssue.title}
            </SanitizedHtml>{' '}
            <span className="fgColor-muted">#{parentIssue.number}</span>
          </>
        )
      }

      const ParentIssueTitle = () => {
        const {openParentIssue} = useOpenParentIssue()
        return (
          <>
            {parentIssue.url ? (
              <Link
                href={parentIssue.url}
                onClick={event => {
                  event.stopPropagation()
                  // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
                  if (event.metaKey || event.shiftKey || event.button === 1) return
                  event.preventDefault()
                  openParentIssue(parentIssue)
                }}
              >
                <ParentIssueTitleText />
              </Link>
            ) : (
              <ParentIssueTitleText />
            )}
          </>
        )
      }

      return (
        <StandardSlicerItem
          key={parentIssue.id}
          isActive={sliceValue === parentIssue.nwoReference}
          onSelect={() => onSliceValueChange(parentIssue.nwoReference)}
          icon={
            <ItemState
              isDraft={false}
              state={parentIssue.state}
              stateReason={parentIssue.stateReason}
              type={ItemType.Issue}
              className="mr-2"
            />
          }
          title={<ParentIssueTitle />}
          wrapTrailingContent
          trailingContent={
            parentIssue.subIssueList ? (
              <SubIssuesProgressBar
                total={parentIssue.subIssueList.total}
                completed={parentIssue.subIssueList.completed}
                percentCompleted={parentIssue.subIssueList.percentCompleted}
              />
            ) : undefined
          }
        />
      )
    }
    case MemexColumnDataType.IssueType: {
      const fieldGrouping = group.sourceObject
      const value = fieldGrouping.value.name
      return (
        <StandardSlicerItem
          key={fieldGrouping.value.id}
          isActive={sliceValue === value}
          onSelect={() => onSliceValueChange(value)}
          title={value}
          metadata={<ListItemCountMetadata count={count} />}
        />
      )
    }
    case MemexColumnDataType.Repository: {
      const fieldGrouping = group.sourceObject
      const value = fieldGrouping.value.nameWithOwner
      return (
        <StandardSlicerItem
          key={fieldGrouping.value.id}
          isActive={sliceValue === value}
          onSelect={() => onSliceValueChange(value)}
          icon={<RepositoryIcon repository={fieldGrouping.value} className="fgColor-muted" />}
          title={value}
          metadata={<ListItemCountMetadata count={count} />}
        />
      )
    }
    case MemexColumnDataType.Text: {
      const fieldGrouping = group.sourceObject
      const value = fieldGrouping.value.text.raw

      return (
        <StandardSlicerItem
          key={value}
          isActive={sliceValue === value}
          onSelect={() => onSliceValueChange(value)}
          title={sanitizeTextInputHtmlString(fieldGrouping.value.text.html)}
          metadata={<ListItemCountMetadata count={count} />}
        />
      )
    }
    case MemexColumnDataType.Number: {
      const valueString = group.sourceObject.value.number.value.toString()
      return (
        <StandardSlicerItem
          key={group.sourceObject.value.number.value.toString()}
          onSelect={() => onSliceValueChange(valueString)}
          isActive={sliceValue === valueString}
          title={valueString}
          metadata={<ListItemCountMetadata count={count} />}
        />
      )
    }
    case MemexColumnDataType.Date: {
      const date = group.sourceObject.value.date.value
      const title = formatDateString(date)
      const value = formatISODateString(date)
      const todayLabel = isToday(value) ? 'Today' : undefined
      return (
        <StandardSlicerItem
          key={date.toString()}
          onSelect={() => onSliceValueChange(value)}
          isActive={sliceValue === value}
          title={title}
          metadata={
            <>
              {todayLabel && (
                <div>
                  <Label className={styles.todayLabel}>{todayLabel}</Label>
                </div>
              )}
              <ListItemCountMetadata count={count} />
            </>
          }
        />
      )
    }
    case MemexColumnDataType.Iteration:
      return (
        <SlicerIterationItem
          key={group.sourceObject.value.iteration.id}
          fieldGrouping={group.sourceObject}
          count={count}
          onSliceValueChange={onSliceValueChange}
          sliceValue={sliceValue}
        />
      )
    default:
      return null
  }
}

export const SlicerGroupByItems = ({
  sliceValue,
  onSliceValueChange,
  slicerItems,
  showEmptySlicerItems,
  setShowEmptySlicerItems,
}: SlicerItemCommonProps & {
  slicerItems: Array<SlicerItemGroup>
  showEmptySlicerItems: boolean
  setShowEmptySlicerItems: (value: boolean) => void
}) => {
  const [nonEmptySlicerItems, emptySlicerItems] = partition(slicerItems, item => item.totalCount.value > 0)
  const hasEmptySlicerItems = emptySlicerItems.length > 0
  const dataType = slicerItems[0]?.sourceObject.dataType
  const hasLeadingIcons = !(dataType && fieldsWithNoLeadingIcon.has(dataType))

  return (
    <>
      <ListContainer hasLeadingIcons={hasLeadingIcons}>
        <Heading as="h2" className="sr-only">
          Project items group
        </Heading>
        <ActionList aria-labelledby="slicer-panel-title" showDividers>
          {nonEmptySlicerItems.map(group => getSlicerItem({group, sliceValue, onSliceValueChange}))}
          {showEmptySlicerItems &&
            emptySlicerItems.map(group => getSlicerItem({group, sliceValue, onSliceValueChange}))}
        </ActionList>
      </ListContainer>
      <ToggleItemsButton
        hasEmptySlicerItems={hasEmptySlicerItems}
        showEmptySlicerItems={showEmptySlicerItems}
        setShowEmptySlicerItems={setShowEmptySlicerItems}
      />
    </>
  )
}

/* Tracked By */

const SlicerNoTrackedByItem = ({onSliceValueChange, sliceValue}: SlicerItemCommonProps) => (
  <StandardSlicerItem
    onSelect={() => onSliceValueChange(NO_SLICE_VALUE)}
    isActive={sliceValue === NO_SLICE_VALUE}
    title={TrackedByResources.noTrackedBy}
  />
)

const SlicerTrackedByItem = ({
  item,
  onSliceValueChange,
  sliceValue,
  onOpenSidePanel,
}: SlicerItemCommonProps & {
  item: IssueModel
  onOpenSidePanel: (e: React.MouseEvent<HTMLAnchorElement>, item: IssueModel) => void
}) => {
  const columnData = item.columns
  const repo = columnData.Repository
  const title = columnData.Title
  const tracks = columnData.Tracks
  const issueSuffix = title && 'number' in title.value ? `#${title.value.number}` : ''
  const displayName = repo ? `${repo.nameWithOwner}${issueSuffix}` : ''
  const isActive = sliceValue === displayName
  const issueId = item.content.id

  // Tracked by items allow users to add missing child items to the project
  const {tasklist_block} = useEnabledFeatures()
  const {getChildrenTrackedByParent, parentIssuesById} = useTrackedByItemsContext()
  const itemsNotInProjectCount = tasklist_block ? parentIssuesById.get(issueId)?.count ?? 0 : 0

  // Show percent complete tooltip over the tracks token
  const tracksTokenRef = useRef<HTMLButtonElement>(null)
  const [contentProps, Trackstooltip] = usePortalTooltip({
    contentRef: tracksTokenRef,
    direction: 'n',
    'aria-label': tracks?.total
      ? Resources.progressPercentCount(Math.floor((tracks.completed / tracks.total) * 100))
      : undefined,
  })

  useEffect(() => {
    if (tasklist_block && isActive) {
      getChildrenTrackedByParent(issueId)
    }
  }, [tasklist_block, issueId, getChildrenTrackedByParent, isActive])

  const icon = title?.contentType === ItemType.Issue ? <ItemStateForTitle title={title} /> : undefined
  const metadata = tracks ? (
    <Stack align="center" gap="condensed" justify="end">
      <TracksToken ref={tracksTokenRef} sx={{cursor: 'pointer', mr: 2}} progress={tracks} {...contentProps} />
      {Trackstooltip}
    </Stack>
  ) : undefined

  if (isActive) {
    return (
      <ActionList.Item
        onSelect={() => onSliceValueChange(displayName)}
        className={clsx(isActive && styles.actionListItemActive, styles.actionListItem, 'active-item')}
      >
        <div className={styles.actionListItemContainer}>
          <div className={clsx(styles.leadingContent, styles.leadingVisual)}>
            <div className={styles.icon}>{icon}</div>
          </div>
          <div className={styles.mainContent}>
            <div className="flex-1 pr-2 py-2 text-left">
              <SanitizedHtml as="h3" className={styles.title}>
                {item.getHtmlTitle()}
              </SanitizedHtml>
              {displayName && (
                <>
                  <Link
                    className={styles.link}
                    target="_blank"
                    rel="noreferrer"
                    href={item.content.url}
                    onClick={e => onOpenSidePanel(e, item)}
                    {...testIdProps('issue-link')}
                  >
                    {displayName}
                  </Link>
                  {itemsNotInProjectCount ? (
                    <div className={styles.addMissingItemsButton}>
                      <TrackedByMissingIssuesButton
                        trackedBy={issueId}
                        invisibleButtonVariant={false}
                        ui={SlicerPanelUI}
                      />
                    </div>
                  ) : null}
                </>
              )}
            </div>
            {metadata}
          </div>
        </div>
      </ActionList.Item>
    )
  }

  return (
    <StandardSlicerItem
      onSelect={() => onSliceValueChange(displayName)}
      isActive={isActive}
      icon={icon}
      title={item.getHtmlTitle()}
      description={displayName ? <div className={styles.link}>{displayName}</div> : undefined}
      metadata={metadata}
    />
  )
}

// Returns a Tracked by item for IssueModels and a "No Tracked by" item for undefined
const getSlicerTrackedByItem = ({
  item,
  ...args
}: {
  item: MemexItemModel | undefined
  sliceValue: SliceValue
  onSliceValueChange: (newValue: SliceValue) => void
  onOpenSidePanel: (e: React.MouseEvent<HTMLAnchorElement>, item: IssueModel) => void
}) => {
  switch (item?.contentType) {
    case ItemType.Issue:
      return <SlicerTrackedByItem key={item.id} item={item} {...args} />
    case undefined:
      return <SlicerNoTrackedByItem key={'no-tracked-by-item'} {...args} />
    default:
      return null
  }
}

// Get filtered items inside of child component to avoid unnecessary filter operations for other slicer types
// Avoid nesting filter input inside of the list view because the suggestion list disrupts focus management
export const SlicerTrackedByItems = ({
  sliceValue,
  onSliceValueChange,
  onOpenSidePanel,
}: SlicerItemCommonProps & {
  onOpenSidePanel: (e: React.MouseEvent<HTMLAnchorElement>, item: IssueModel) => void
}) => {
  const {filteredItems} = useFilteredItems({applyTransientFilter: 'exclude'})

  const sliceItems = filteredItems.map(item =>
    getSlicerTrackedByItem({item, sliceValue, onSliceValueChange, onOpenSidePanel}),
  )
  const noTrackedByItem = getSlicerTrackedByItem({item: undefined, sliceValue, onSliceValueChange, onOpenSidePanel})
  sliceItems.push(noTrackedByItem)

  return (
    <>
      <ProjectInputWithSearchContext
        filterCount={useDeferredValue(filteredItems.length)}
        hideSaveButton
        hideResetChangesButton
        {...testIdProps('slicer-panel-filter-input')}
      />
      <ListContainer>
        <Heading as="h2" className="sr-only">
          Project filtered items
        </Heading>
        <ActionList aria-labelledby="slicer-panel-title" showDividers>
          {sliceItems}
        </ActionList>
      </ListContainer>
    </>
  )
}

export const SlicerIterationItems = ({
  slicerItems,
  sliceValue,
  onSliceValueChange,
  showEmptySlicerItems,
  setShowEmptySlicerItems,
}: SlicerItemCommonProps & {
  slicerItems: Array<SlicerItemGroup>
  showEmptySlicerItems: boolean
  setShowEmptySlicerItems: (value: boolean) => void
}) => {
  const iterations: Array<Iteration> = []
  const iterationGroupsMap = new Map<string, SlicerItemGroup>()
  let emptyGroup: SlicerItemGroup | null = null

  for (const item of slicerItems) {
    if (item.sourceObject.dataType === MemexColumnDataType.Iteration) {
      if (item.sourceObject.kind !== 'empty') {
        const iteration = item.sourceObject.value.iteration
        iterations.push(iteration)
        iterationGroupsMap.set(iteration.id, item)
      } else {
        emptyGroup = item
      }
    }
  }

  const partitionedIterations = partitionAllIterations(iterations)

  if (!partitionedIterations['iterations'].length && !partitionedIterations['completedIterations'].length) {
    return null
  }

  const hasEmptySlicerItems = slicerItems.some(item => item.totalCount.value === 0)

  return (
    <>
      <ListContainer>
        <Heading as="h2" className="sr-only">
          Project iterations list
        </Heading>
        <ActionList aria-labelledby="slicer-panel-title" showDividers>
          {partitionedIterations['iterations'].length > 0 && (
            <>
              {partitionedIterations['iterations'].map(iteration => {
                const slicerItem = iterationGroupsMap.get(iteration.id)
                if (!slicerItem || (!showEmptySlicerItems && !slicerItem.totalCount.value)) return null

                return getSlicerItem({group: slicerItem, sliceValue, onSliceValueChange})
              })}
            </>
          )}
          {emptyGroup && getSlicerItem({group: emptyGroup, sliceValue, onSliceValueChange})}
        </ActionList>
        {partitionedIterations['completedIterations'].length > 0 && (
          <>
            <div data-testid="completed-iteration-header" className={styles.completedIterationHeading}>
              {Resources.iterationLabel.completed}
            </div>
            <ActionList aria-label="Completed iterations">
              {partitionedIterations['completedIterations'].map(iteration => {
                const slicerItem = iterationGroupsMap.get(iteration.id)
                if (!slicerItem || (!showEmptySlicerItems && !slicerItem.totalCount.value)) return null

                return slicerItem && getSlicerItem({group: slicerItem, sliceValue, onSliceValueChange})
              })}
            </ActionList>
          </>
        )}
      </ListContainer>
      <ToggleItemsButton
        hasEmptySlicerItems={hasEmptySlicerItems}
        showEmptySlicerItems={showEmptySlicerItems}
        setShowEmptySlicerItems={setShowEmptySlicerItems}
      />
    </>
  )
}

const ToggleItemsButton = ({
  hasEmptySlicerItems,
  showEmptySlicerItems,
  setShowEmptySlicerItems,
}: {
  hasEmptySlicerItems: boolean
  showEmptySlicerItems: boolean
  setShowEmptySlicerItems: (showEmptySlicerItems: boolean) => void
}) => {
  const toggleEmptySlicerItems = () => setShowEmptySlicerItems(!showEmptySlicerItems)

  if (!hasEmptySlicerItems) return null

  return (
    <Button
      onClick={toggleEmptySlicerItems}
      size="small"
      variant="invisible"
      className={styles.toggleEmptyButton}
      {...testIdProps('toggle-empty-slicer-items')}
    >
      {showEmptySlicerItems ? 'Hide' : 'Show'} empty values
    </Button>
  )
}
