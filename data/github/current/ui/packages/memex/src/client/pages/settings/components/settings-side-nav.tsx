import {testIdProps} from '@github-ui/test-id-props'
import {GearIcon, PeopleIcon} from '@primer/octicons-react'
import {NavList} from '@primer/react'
import {memo, type MouseEvent, useCallback, useRef, useState} from 'react'

import type {MemexProjectColumnId} from '../../../api/columns/contracts/memex-column'
import {SettingsOpen, SettingsOpenField, SettingsOpenSidebarUI} from '../../../api/stats/contracts'
import {AddColumnModal} from '../../../components/react_table/add-column-modal'
import {NavLinkActionListItem} from '../../../components/react-router/action-list-nav-link-item'
import {ViewerPrivileges} from '../../../helpers/viewer-privileges'
import {usePostStats} from '../../../hooks/common/use-post-stats'
import type {ColumnModel} from '../../../models/column-model'
import {useNavigate} from '../../../router'
import {useProjectRouteParams} from '../../../router/use-project-route-params'
import {PROJECT_SETTINGS_ACCESS_ROUTE, PROJECT_SETTINGS_FIELD_ROUTE, PROJECT_SETTINGS_ROUTE} from '../../../routes'
import {useAllColumns} from '../../../state-providers/columns/use-all-columns'
import {ColumnListNav} from './column-list-nav'

// Note: this code will replace SettingsSideNav once the reordering is validated on production
export const ReorderableSettingsSideNav = memo(function ReorderableSettingsSideNav() {
  const {allColumns} = useAllColumns()

  const {hasAdminPermissions} = ViewerPrivileges()
  const {postStats} = usePostStats()

  const [show, setShow] = useState(false)

  const anchorRef = useRef<HTMLButtonElement>(null)
  const navigate = useNavigate()

  const onNewField = useCallback(() => setShow(open => !open), [])

  const onFieldNavCallback = useCallback(
    (memexProjectColumnId: MemexProjectColumnId, e: MouseEvent) => {
      postStats({
        name: SettingsOpenField,
        ui: SettingsOpenSidebarUI,
        memexProjectColumnId,
        context: `${e.type}: ${e.currentTarget.tagName}`,
      })
    },
    [postStats],
  )

  const projectRouteParams = useProjectRouteParams()
  return (
    <>
      <NavList {...testIdProps('settings-side-nav')} aria-label="Settings">
        <NavLinkActionListItem
          end
          to={PROJECT_SETTINGS_ROUTE.generatePath(projectRouteParams)}
          {...testIdProps('general-settings-item')}
          onClick={(e: React.MouseEvent) => {
            postStats({
              name: SettingsOpen,
              ui: SettingsOpenSidebarUI,
              context: `${e.type}: ${e.currentTarget.tagName}`,
            })
          }}
        >
          {/* eslint-disable-next-line primer-react/direct-slot-children */}
          <NavList.LeadingVisual>
            <GearIcon />
          </NavList.LeadingVisual>
          Project settings
        </NavLinkActionListItem>
        {hasAdminPermissions && (
          <NavLinkActionListItem
            to={PROJECT_SETTINGS_ACCESS_ROUTE.generatePath(projectRouteParams)}
            {...testIdProps('manage-access-item')}
          >
            {/* eslint-disable-next-line primer-react/direct-slot-children */}
            <NavList.LeadingVisual>
              <PeopleIcon />
            </NavList.LeadingVisual>
            Manage access
          </NavLinkActionListItem>
        )}

        <ColumnListNav
          columns={allColumns}
          addNewAnchorRef={anchorRef}
          onNewField={onNewField}
          onFieldNavCallback={onFieldNavCallback}
        />
      </NavList>

      <AddColumnModal
        key={allColumns.length}
        isOpen={show}
        setOpen={setShow}
        anchorRef={anchorRef}
        onSave={useCallback(
          (field: ColumnModel): void => {
            navigate(PROJECT_SETTINGS_FIELD_ROUTE.generatePath({...projectRouteParams, fieldId: field.id}))
          },
          [navigate, projectRouteParams],
        )}
      />
    </>
  )
})
