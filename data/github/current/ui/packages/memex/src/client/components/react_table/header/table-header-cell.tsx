import {useDndContext} from '@github-ui/drag-and-drop'
import {testIdProps} from '@github-ui/test-id-props'
import {
  EyeClosedIcon,
  FilterIcon,
  GearIcon,
  KebabHorizontalIcon,
  MultiSelectIcon,
  RowsIcon,
  SortAscIcon,
  SortDescIcon,
  XIcon,
} from '@primer/octicons-react'
import {ActionList, ActionMenu, type BoxProps, Button, IconButton, themeGet} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {memo, useCallback, useMemo, useRef, useState} from 'react'
import {flushSync} from 'react-dom'
import type {ColumnInstance} from 'react-table'

import {MemexColumnDataType} from '../../../api/columns/contracts/memex-column'
import {
  type FieldGroupUIType,
  FieldHideName,
  FieldSortAsc,
  FieldSortDesc,
  TableHeaderMenuUI,
} from '../../../api/stats/contracts'
import type {SortDirection} from '../../../api/view/contracts'
import {useSliceBy} from '../../../features/slicing/hooks/use-slice-by'
import {not_typesafe_nonNullAssertion} from '../../../helpers/non-null-assertion'
import {ViewerPrivileges} from '../../../helpers/viewer-privileges'
import {usePostStats} from '../../../hooks/common/use-post-stats'
import useBodyClass from '../../../hooks/use-body-class'
import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import {useSortedBy} from '../../../hooks/use-sorted-by'
import {useViews} from '../../../hooks/use-views'
import {useVisibleFields} from '../../../hooks/use-visible-fields'
import {
  isFilterableColumn,
  isGroupableColumn,
  isSliceableColumn,
  isSortableColumn,
} from '../../../models/column-capabilities'
import type {ColumnModel} from '../../../models/column-model'
import {useNavigate} from '../../../router'
import {useProjectRouteParams} from '../../../router/use-project-route-params'
import {PROJECT_SETTINGS_FIELD_ROUTE} from '../../../routes'
import {Resources} from '../../../strings'
import {getColumnSortedAscendingDescription, getColumnSortedDescendingDescription} from '../../column-detail-helpers'
import {ColumnSortIcon} from '../../common/column-sort-icon'
import {useSearch} from '../../filter-bar/search-context'
import {MoveToLeftAction, MoveToRightAction} from '../../move-to-actions'
import {SlicerIcon} from '../../slice-by-menu'
import {describeSortRanking} from '../../sorted-by'
import {useGetVisibleRows} from '../hooks/use-visible-rows'
import {focusCell, focusSearchInput, useStableTableNavigation} from '../navigation'
import {useTableCellBulkSelectionActions} from '../table-cell-bulk-selection'
import type {TableDataType} from '../table-data-type'
import {useTableState} from '../table-provider'
import {columnHeaderTestId} from '../test-identifiers'
import {HeaderGridCell} from './header-grid-cell'
import {HeaderGridCellLayout} from './header-grid-cell-layout'
import styles from './table-header-cell.module.css'

function getSortDirectionLabel(canSort: boolean, descending: boolean | undefined) {
  if (!canSort) {
    return undefined
  } else if (descending === undefined) {
    return 'none'
  } else if (descending) {
    return 'descending'
  } else {
    return 'ascending'
  }
}

type TableHeaderCellProps = {
  header: ColumnInstance<TableDataType>
  headers: Array<ColumnInstance<TableDataType>>
  groupByColumn: (column: ColumnInstance<TableDataType>, ui: FieldGroupUIType) => void
  sliceByColumn: (column: ColumnModel) => void
  height: number
}

/**
 * An individual table column header. Only rendered if a columnModel is present.
 */
export const TableHeaderCell = memo((props: TableHeaderCellProps) => {
  const columnModel = not_typesafe_nonNullAssertion(props.header.columnModel)
  const {currentView} = useViews()
  const {groupByColumn, header, sliceByColumn} = props
  const anchorRef = useRef<HTMLButtonElement>(null)
  const [menuOpen, setMenuOpen] = useState(false)
  const {sortBy} = useTableState()
  const {canSort, isSorted, isSortedDesc, sortedIndex} = header
  const {appendFilter, focusFilterInput} = useSearch()
  const {postStats} = usePostStats()
  const {hideField, moveField, visibleFields, visibleFieldIndexMap} = useVisibleFields()
  const {hasWritePermissions} = ViewerPrivileges()
  const {setColumnSort} = useSortedBy()
  const bulkSelectActions = useTableCellBulkSelectionActions()
  const getVisibleRows = useGetVisibleRows()
  const {sliceField} = useSliceBy()
  const {memex_column_menu_position} = useEnabledFeatures()

  const isSliced = sliceField === columnModel
  const isTitleColumn = columnModel.dataType === MemexColumnDataType.Title
  const isSingleSelect = columnModel.dataType === MemexColumnDataType.SingleSelect
  const isSubIssuesProgress = columnModel.dataType === MemexColumnDataType.SubIssuesProgress

  const onHideColumn = useCallback(() => {
    if (!currentView) return

    hideField(currentView.number, columnModel)
    postStats({
      name: FieldHideName,
      ui: TableHeaderMenuUI,
      memexProjectColumnId: columnModel.id,
    })
  }, [columnModel, hideField, postStats, currentView])

  const sortByDirection = useCallback(
    (direction: SortDirection) => {
      if (!columnModel) return

      const isNewSortDesc = direction === 'desc'

      // Clear sort if target direction is same as current direction
      const resolvedDirection = isNewSortDesc === isSortedDesc ? null : direction

      const expectedIndex = isSorted ? sortedIndex : 0
      setColumnSort(columnModel, resolvedDirection)

      // Close the cell options menu
      setMenuOpen(false)

      postStats({
        name: isNewSortDesc ? FieldSortDesc : FieldSortAsc,
        ui: TableHeaderMenuUI,
        context: columnModel.id,
        index: expectedIndex,
      })
    },
    [columnModel, isSortedDesc, isSorted, sortedIndex, setColumnSort, setMenuOpen, postStats],
  )

  const GroupedLabel = useCallback(() => {
    if (!props.header.isGrouped) return null

    return (
      <div className={styles.Box} {...testIdProps(`grouped-label-${columnModel.name}`)}>
        <Octicon icon={RowsIcon} />
      </div>
    )
  }, [columnModel.name, props.header.isGrouped])

  const SortedLabel = useCallback(() => {
    const showSortRank = sortBy.length > 1
    const sortRankDescription = showSortRank ? `${describeSortRanking(sortedIndex)} ` : ''

    if (!isSorted) return null

    return (
      <Button
        variant="invisible"
        size="small"
        aria-label={`Change ${sortRankDescription}sort direction to ${isSortedDesc ? 'ascending' : 'descending'}`}
        onClick={() => sortByDirection(isSortedDesc ? 'asc' : 'desc')}
        className={styles.Button}
        {...testIdProps(`sorted-label-${columnModel.id}`)}
      >
        <ColumnSortIcon direction={isSortedDesc ? 'desc' : 'asc'} index={showSortRank ? sortedIndex : undefined} />
      </Button>
    )
  }, [isSorted, isSortedDesc, columnModel.id, sortBy.length, sortedIndex, sortByDirection])

  const SlicedLabel = useCallback(() => {
    if (!isSliced) return null

    return (
      <div className={styles.Box} {...testIdProps(`sliced-label-${columnModel.name}`)}>
        <Octicon icon={SlicerIcon} />
      </div>
    )
  }, [columnModel.name, isSliced])

  const ascendingDescription = getColumnSortedAscendingDescription(columnModel.dataType)
  const descendingDescription = getColumnSortedDescendingDescription(columnModel.dataType)

  const sortMenuOptions = useMemo(() => {
    if (!canSort) return []

    const isSortedAscending = isSorted && !isSortedDesc
    const isSortedDescending = isSorted && isSortedDesc

    const isSortDisabled = !isSortableColumn(columnModel.dataType)

    return [
      <ActionList.Item
        key={`sort-ascending-${columnModel.id}`}
        onSelect={() => sortByDirection('asc')}
        disabled={isSortDisabled}
        sx={{fontWeight: isSortedAscending ? themeGet('fontWeights.bold') : themeGet('fontWeights.normal')}}
        aria-describedby={`sort-description-asc-${columnModel.id}`}
        {...testIdProps(`sort-toggle-asc-${columnModel.id}`)}
      >
        <ActionList.LeadingVisual>
          <SortAscIcon />
        </ActionList.LeadingVisual>

        <span>
          {isSortedAscending
            ? Resources.tableHeaderContextMenu.sortAscendingActive
            : Resources.tableHeaderContextMenu.sortAscending}
        </span>

        <ActionList.TrailingVisual>{isSortedAscending && <XIcon />}</ActionList.TrailingVisual>
      </ActionList.Item>,

      <span
        key={`sort-description-asc-${columnModel.id}`}
        id={`sort-description-asc-${columnModel.id}`}
        className="sr-only"
      >
        {ascendingDescription}
      </span>,

      <ActionList.Item
        key={`sort-descending-${columnModel.id}`}
        onSelect={() => sortByDirection('desc')}
        disabled={isSortDisabled}
        sx={{fontWeight: isSortedDescending ? themeGet('fontWeights.bold') : themeGet('fontWeights.normal')}}
        aria-describedby={`sort-description-desc-${columnModel.id}`}
        {...testIdProps(`sort-toggle-desc-${columnModel.id}`)}
      >
        <ActionList.LeadingVisual>
          <SortDescIcon />
        </ActionList.LeadingVisual>

        <span>
          {isSortedDescending
            ? Resources.tableHeaderContextMenu.sortDescendingActive
            : Resources.tableHeaderContextMenu.sortDescending}
        </span>

        <ActionList.TrailingVisual>{isSortedDescending && <XIcon />}</ActionList.TrailingVisual>
      </ActionList.Item>,

      <span
        key={`sort-description-desc-${columnModel.id}`}
        id={`sort-description-desc-${columnModel.id}`}
        className="sr-only"
      >
        {descendingDescription}
      </span>,
    ]
  }, [
    canSort,
    isSorted,
    isSortedDesc,
    columnModel.id,
    columnModel.dataType,
    ascendingDescription,
    descendingDescription,
    sortByDirection,
  ])

  const navigate = useNavigate()
  const projectRouteParams = useProjectRouteParams()
  const {navigationDispatch} = useStableTableNavigation()

  const onCreateFilter = useCallback(
    (filterKeyword: string, e: React.KeyboardEvent<HTMLElement> | React.MouseEvent<HTMLElement>) => {
      appendFilter(filterKeyword)
      focusFilterInput()
      navigationDispatch(focusSearchInput())

      // Stop this event from closing the search suggestions (as an outside click).
      e.stopPropagation()
    },
    [appendFilter, focusFilterInput, navigationDispatch],
  )

  const moveToLeft = useCallback(() => {
    if (!currentView) {
      return
    }

    const currentIndex = visibleFields.indexOf(columnModel)

    moveField(currentView.number, columnModel, currentIndex - 1)
  }, [columnModel, currentView, moveField, visibleFields])

  const moveToRight = useCallback(() => {
    if (!currentView) {
      return
    }

    const currentIndex = visibleFields.indexOf(columnModel)

    moveField(currentView.number, columnModel, currentIndex + 1)
  }, [columnModel, currentView, moveField, visibleFields])

  const createFilterOptions = useMemo(() => {
    const defaultOptions = [
      <ActionList.Item
        key={`filter-by-values-${columnModel.id}`}
        onSelect={event => {
          // eslint-disable-next-line @eslint-react/dom/no-flush-sync
          flushSync(() => {
            setMenuOpen(false)
          })
          onCreateFilter(columnModel.name, event)
        }}
        disabled={!isFilterableColumn(columnModel.dataType)}
        {...testIdProps('create-filter-trigger')}
      >
        <ActionList.LeadingVisual>
          <FilterIcon />
        </ActionList.LeadingVisual>
        {Resources.tableHeaderContextMenu.filterValues}
      </ActionList.Item>,
    ]
    if (isTitleColumn) {
      defaultOptions.push(
        <ActionList.Item
          key={`filter-by-is-${columnModel.id}`}
          onSelect={event => {
            onCreateFilter('is', event)
            setMenuOpen(false)
          }}
          {...testIdProps('create-is-filter-trigger')}
        >
          <ActionList.LeadingVisual>
            <FilterIcon />
          </ActionList.LeadingVisual>
          {Resources.tableHeaderContextMenu.filterByType}
        </ActionList.Item>,
      )
    }
    return defaultOptions
  }, [columnModel.id, columnModel.dataType, columnModel.name, isTitleColumn, onCreateFilter, setMenuOpen])

  const onGroupByColumn = useCallback(() => {
    groupByColumn(props.header, TableHeaderMenuUI)
    setMenuOpen(false)
  }, [groupByColumn, props.header, setMenuOpen])

  const groupByOptions = useMemo(() => {
    if (!props.header.canGroupBy) return []

    return [
      <ActionList.Item
        key={`group-by-${columnModel.id}`}
        onSelect={onGroupByColumn}
        sx={{fontWeight: props.header.isGrouped ? themeGet('fontWeights.bold') : themeGet('fontWeights.normal')}}
        disabled={!isGroupableColumn(columnModel.dataType)}
        {...testIdProps(`group-by-trigger`)}
      >
        <ActionList.LeadingVisual>
          <RowsIcon />
        </ActionList.LeadingVisual>
        {props.header.isGrouped
          ? Resources.tableHeaderContextMenu.groupByActive
          : Resources.tableHeaderContextMenu.groupByValues}
        <ActionList.TrailingVisual>{props.header.isGrouped && <XIcon />}</ActionList.TrailingVisual>
      </ActionList.Item>,
    ]
  }, [props.header.canGroupBy, props.header.isGrouped, columnModel.id, columnModel.dataType, onGroupByColumn])

  const onSliceByColumn = useCallback(() => {
    sliceByColumn(columnModel)
    setMenuOpen(false)
  }, [columnModel, setMenuOpen, sliceByColumn])

  const sliceByOptions = useMemo(() => {
    if (!isSliceableColumn(columnModel.dataType)) return []

    return [
      <ActionList.Item
        key={`slice-by-${columnModel.id}`}
        onSelect={onSliceByColumn}
        sx={{fontWeight: isSliced ? themeGet('fontWeights.bold') : themeGet('fontWeights.normal')}}
        disabled={!isSliceableColumn(columnModel.dataType)}
        {...testIdProps(`slice-by-trigger`)}
      >
        <ActionList.LeadingVisual>
          <SlicerIcon />
        </ActionList.LeadingVisual>
        {Resources.tableHeaderContextMenu.sliceByValues}
        <ActionList.TrailingVisual>{isSliced && <XIcon />}</ActionList.TrailingVisual>
      </ActionList.Item>,
    ]
  }, [columnModel, onSliceByColumn, isSliced])

  const resizeProps = props.header.getResizerProps()

  const onMouseDown: React.MouseEventHandler<HTMLElement> = useCallback(
    e => {
      e.stopPropagation()
      resizeProps.onMouseDown(e)
    },
    [resizeProps],
  )

  const ColumnResizeDragger = useCallback(() => {
    if (!props.header.canResize || !hasWritePermissions) return null

    return (
      <>
        {/* eslint-disable-next-line jsx-a11y/no-static-element-interactions */}
        <div
          {...resizeProps}
          onMouseDown={onMouseDown}
          className={styles.Box_1}
          {...testIdProps(`${columnModel.name}-column-resizer`)}
        />
      </>
    )
  }, [onMouseDown, props.header.canResize, resizeProps, columnModel, hasWritePermissions])

  const dndContext = useDndContext()
  const headerProps = props.header.getHeaderProps({
    className: `${!hasWritePermissions ? 'readonly' : dndContext.active ? '' : 'hoverable'}`,
    style: {minWidth: props.header.width, height: props.height},
  })

  useBodyClass('is-resizing', props.header.isResizing)

  const selectColumn = useCallback(() => {
    const firstRow = getVisibleRows()[0]
    if (!firstRow || !bulkSelectActions) return

    // setTimeout is a hack to get around the return-focus behavior of the action menu by focusing the cell after the menu closes
    setTimeout(() => {
      // Technically only the focus dispatch needs to be async, but it feels faster if the selection & focus happen at the same time
      bulkSelectActions.selectColumn(props.header.id)
      navigationDispatch(focusCell(firstRow.id, props.header.id))
    })
  }, [bulkSelectActions, navigationDispatch, props.header.id, getVisibleRows])

  const positionActions = useMemo(() => {
    if (memex_column_menu_position && hasWritePermissions) {
      const isFirstColumn = visibleFieldIndexMap.get(columnModel.id) === 0
      const isLastColumn = visibleFieldIndexMap.get(columnModel.id) === visibleFields.length - 1

      return [
        <MoveToLeftAction
          key="moveToLeft"
          disabled={isFirstColumn}
          isLeftmostColumn={isFirstColumn}
          onSelect={moveToLeft}
        />,
        <MoveToRightAction
          key="moveToRight"
          disabled={isLastColumn}
          isRightmostColumn={isLastColumn}
          onSelect={moveToRight}
        />,
      ]
    }
    return []
  }, [
    memex_column_menu_position,
    hasWritePermissions,
    visibleFieldIndexMap,
    columnModel.id,
    visibleFields.length,
    moveToLeft,
    moveToRight,
  ])

  return useMemo(() => {
    const headerCellStyles: BoxProps['sx'] = {
      boxShadow: theme =>
        `inset 0 -2px 0 ${
          SortedLabel() || GroupedLabel() || SlicedLabel() ? theme.colors.neutral.emphasis : theme.colors.border.default
        }, inset 0 1px 0 ${theme.colors.border.default}`,
    }

    const {dragProps, ...headerCellProps} = headerProps

    const filterOperations = createFilterOptions
    const groupOperations = [...groupByOptions, ...sliceByOptions]
    const canBulkSelectColumn = bulkSelectActions !== null

    return (
      <HeaderGridCell
        {...headerCellProps}
        {...testIdProps(columnHeaderTestId(props.header.id))}
        aria-sort={getSortDirectionLabel(props.header.canSort, props.header.isSortedDesc)}
      >
        <HeaderGridCellLayout
          sx={{
            ...headerCellStyles,
            height: props.height,
          }}
          ref={dragProps.setNodeRef}
          className={styles.HeaderGridCellLayout}
          {...dragProps.listeners}
        >
          <span className={styles.Text} {...testIdProps(`${columnModel.name}-column-header-name`)}>
            {props.header.render('Header')}
          </span>
          <div className={styles.Box_2}>
            <GroupedLabel />
            <SlicedLabel />
            <SortedLabel />
            <ActionMenu open={menuOpen} onOpenChange={setMenuOpen} anchorRef={anchorRef}>
              <ActionMenu.Anchor>
                <IconButton
                  ref={anchorRef}
                  icon={KebabHorizontalIcon}
                  variant="invisible"
                  size="small"
                  aria-label={`${columnModel.name} column options`}
                  className={styles.IconButton}
                  {...testIdProps(`${columnModel.name}-column-menu-trigger`)}
                />
              </ActionMenu.Anchor>
              <ActionMenu.Overlay {...testIdProps(`${columnModel.name}-column-menu`)} initialFocusRef={anchorRef}>
                <ActionList>
                  {canBulkSelectColumn && (
                    <ActionList.Item onSelect={selectColumn}>
                      <ActionList.LeadingVisual>
                        <MultiSelectIcon />
                      </ActionList.LeadingVisual>
                      {Resources.tableHeaderContextMenu.selectColumn}
                    </ActionList.Item>
                  )}

                  {sortMenuOptions.length > 0 && <ActionMenu.Divider />}
                  {sortMenuOptions}

                  {filterOperations.length > 0 && <ActionMenu.Divider />}
                  {filterOperations}

                  {groupOperations.length > 0 && <ActionMenu.Divider />}
                  {groupOperations}

                  {!isTitleColumn && (
                    <>
                      <ActionMenu.Divider />
                      <ActionList.Item onSelect={onHideColumn} disabled={isSorted}>
                        <ActionList.LeadingVisual>
                          <EyeClosedIcon />
                        </ActionList.LeadingVisual>
                        {Resources.tableHeaderContextMenu.hideField}
                      </ActionList.Item>
                    </>
                  )}

                  {hasWritePermissions && (columnModel.userDefined || isSingleSelect || isSubIssuesProgress) && (
                    <>
                      <ActionList.Divider />
                      <ActionList.Item
                        onSelect={() => {
                          navigate({
                            pathname: PROJECT_SETTINGS_FIELD_ROUTE.generatePath({
                              ...projectRouteParams,
                              fieldId: columnModel.id,
                            }),
                          })
                        }}
                        disabled={!hasWritePermissions}
                      >
                        <ActionList.LeadingVisual>
                          <GearIcon />
                        </ActionList.LeadingVisual>
                        {Resources.tableHeaderContextMenu.fieldSettings}
                      </ActionList.Item>
                    </>
                  )}

                  {positionActions.length > 0 && (
                    <>
                      <ActionList.Divider />
                      <ActionList.Group>{positionActions}</ActionList.Group>
                    </>
                  )}
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          </div>
        </HeaderGridCellLayout>
        <ColumnResizeDragger />
      </HeaderGridCell>
    )
  }, [
    headerProps,
    createFilterOptions,
    groupByOptions,
    sliceByOptions,
    bulkSelectActions,
    props.header,
    props.height,
    columnModel.name,
    columnModel.userDefined,
    columnModel.id,
    GroupedLabel,
    SlicedLabel,
    SortedLabel,
    menuOpen,
    selectColumn,
    sortMenuOptions,
    isTitleColumn,
    onHideColumn,
    isSorted,
    hasWritePermissions,
    isSingleSelect,
    isSubIssuesProgress,
    positionActions,
    ColumnResizeDragger,
    setMenuOpen,
    navigate,
    projectRouteParams,
  ])
})

TableHeaderCell.displayName = 'TableHeaderCell'
