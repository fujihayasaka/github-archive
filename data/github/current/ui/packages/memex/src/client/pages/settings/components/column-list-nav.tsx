import {testIdProps} from '@github-ui/test-id-props'
import {PlusIcon} from '@primer/octicons-react'
import {Button, Label, NavList} from '@primer/react'
import {useMemo} from 'react'

import type {MemexProjectColumnId} from '../../../api/columns/contracts/memex-column'
import {getColumnIcon} from '../../../components/column-detail-helpers'
import {NavLinkActionListItem} from '../../../components/react-router/action-list-nav-link-item'
import {getColumnWarning} from '../../../helpers/get-column-warning'
import {isColumnUserEditable} from '../../../helpers/is-column-editable'
import {sortColumnsDeterministically} from '../../../helpers/util'
import type {ColumnModel} from '../../../models/column-model'
import {useProjectRouteParams} from '../../../router/use-project-route-params'
import {PROJECT_SETTINGS_FIELD_ROUTE} from '../../../routes'
import styles from './column-list-nav.module.css'

type ColumnListProps = {
  columns: Array<ColumnModel>
  addNewAnchorRef: React.RefObject<HTMLButtonElement> | null
  /** Called when the "new field" action is selected */
  onNewField: () => void
  onFieldNavCallback?: (memexProjectColumnId: MemexProjectColumnId, event: React.MouseEvent) => void
}

export function ColumnListNav({columns: allColumns, addNewAnchorRef, onNewField, onFieldNavCallback}: ColumnListProps) {
  const columns = useMemo(
    () => allColumns.filter(column => isColumnUserEditable(column)).sort(sortColumnsDeterministically),
    [allColumns],
  )

  return (
    <NavList.Group sx={{position: 'relative', minWidth: 220}} {...testIdProps(`project-column-settings-list`)}>
      <NavList.GroupHeading as="h2" className={styles.heading}>
        <span>Custom fields</span>
        <Button variant="invisible" size="small" leadingVisual={PlusIcon} ref={addNewAnchorRef} onClick={onNewField}>
          New Field
        </Button>
      </NavList.GroupHeading>
      {useMemo(
        () =>
          columns.map(col => (
            <ColumnListItem
              key={col.id}
              column={col}
              onLinkClick={(e: React.MouseEvent) => {
                if (!onFieldNavCallback) return
                onFieldNavCallback(col.id, e)
              }}
            />
          )),
        [columns, onFieldNavCallback],
      )}
    </NavList.Group>
  )
}

type ColumnListItemProps = {
  column: ColumnModel
  onLinkClick: (e: React.MouseEvent) => void
}

function ColumnListItem({column, onLinkClick}: ColumnListItemProps) {
  const projectRouteParams = useProjectRouteParams()
  const Icon = getColumnIcon(column.dataType)
  const showColumnWarning = !!getColumnWarning(column)

  return (
    <NavLinkActionListItem
      to={{
        pathname: PROJECT_SETTINGS_FIELD_ROUTE.generatePath({
          ...projectRouteParams,
          fieldId: encodeURIComponent(column.id),
        }),
      }}
      onClick={onLinkClick}
      {...testIdProps(`ColumnSettingsItem{id: ${column.name}}`)}
    >
      {/* eslint-disable-next-line primer-react/direct-slot-children */}
      <NavList.LeadingVisual
        {...testIdProps(`ColumnSettingsItemIcon{id: ${column.name}}`)}
        className={styles.leadingVisual}
      >
        <Icon />
      </NavList.LeadingVisual>
      {column.name}
      {showColumnWarning && (
        // eslint-disable-next-line primer-react/direct-slot-children
        <NavList.TrailingVisual {...testIdProps(`ColumnSettingsItemBadge{id: ${column.name}}`)}>
          <Label variant="attention">Action required</Label>
        </NavList.TrailingVisual>
      )}
    </NavLinkActionListItem>
  )
}
