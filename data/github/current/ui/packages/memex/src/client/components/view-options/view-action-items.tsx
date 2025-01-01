import {testIdProps} from '@github-ui/test-id-props'
import {GrabberIcon, PencilIcon, TrashIcon, VersionsIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {memo} from 'react'

import {useEnabledFeatures} from '../../hooks/use-enabled-features'
import type {BaseViewState, ViewIsDirtyStates} from '../../hooks/use-view-state-reducer/types'
import {useViews} from '../../hooks/use-views'
import {Resources} from '../../strings'
import {useMoveTabDialog} from './move-tab'

export const ViewActionItems = memo(function ViewActionItems({
  returnFocusRef,
  view,
  handleRenameViewClick,
  handleDuplicateView,
  handleDestroyView,
  viewsLength,
}: {
  returnFocusRef: React.RefObject<HTMLButtonElement>
  view: BaseViewState & ViewIsDirtyStates
  handleRenameViewClick: () => void
  handleDuplicateView: () => Promise<void>
  handleDestroyView: () => Promise<void>
  viewsLength: number
}) {
  const {setMoveTabDialogProps} = useMoveTabDialog()
  const {views} = useViews()
  const {memex_tab_experimental_move_dialog, memex_table_without_limits} = useEnabledFeatures()

  return (
    <>
      {view.isDeleted ? null : (
        <ActionList.Item {...testIdProps('view-options-menu-item-rename-view')} onSelect={handleRenameViewClick}>
          <ActionList.LeadingVisual>
            <PencilIcon />
          </ActionList.LeadingVisual>
          Rename view
        </ActionList.Item>
      )}
      {memex_tab_experimental_move_dialog && memex_table_without_limits && views.length > 1 ? (
        <ActionList.Item
          onSelect={() => {
            setMoveTabDialogProps({selectedTab: view, returnRef: returnFocusRef})
          }}
          aria-label={`Move ${view.name}`}
          {...testIdProps('view-options-advanced-move-dialog')}
        >
          <ActionList.LeadingVisual>
            <GrabberIcon />
          </ActionList.LeadingVisual>
          Move view
        </ActionList.Item>
      ) : null}
      <ActionList.Item {...testIdProps('view-options-menu-item-duplicate-view')} onSelect={handleDuplicateView}>
        <ActionList.LeadingVisual>
          <VersionsIcon />
        </ActionList.LeadingVisual>
        {Resources.duplicateView({isDirty: view.isViewStateDirty})}
      </ActionList.Item>
      <ActionList.Item
        {...testIdProps('view-options-menu-item-delete-view')}
        onSelect={handleDestroyView}
        disabled={viewsLength <= 1}
        variant="danger"
      >
        <ActionList.LeadingVisual>
          <TrashIcon />
        </ActionList.LeadingVisual>
        {view.isDeleted ? 'Remove deleted view' : 'Delete view'}
      </ActionList.Item>
    </>
  )
})
