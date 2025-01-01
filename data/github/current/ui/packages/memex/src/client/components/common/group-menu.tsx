import {
  ArchiveIcon,
  EyeClosedIcon,
  KebabHorizontalIcon,
  NumberIcon,
  PencilIcon,
  TrashIcon,
} from '@primer/octicons-react'
import {ActionList, type ActionListItemProps, ActionMenu, IconButton} from '@primer/react'
import {useCallback, useMemo, useRef} from 'react'

import {ItemType} from '../../api/memex-items/item-type'
import {BoardColumnActionMenuUI} from '../../api/stats/contracts'
import {ViewerPrivileges} from '../../helpers/viewer-privileges'
import {useArchiveMemexItemsWithConfirmation} from '../../hooks/use-archive-memex-items-with-confirmation'
import {useEnabledFeatures} from '../../hooks/use-enabled-features'
import {useRemoveMemexItemWithConfirmation} from '../../hooks/use-remove-memex-items-with-id'
import type {MemexItemModel} from '../../models/memex-item-model'
import {Resources} from '../../strings'
import {MoveToLeftAction, MoveToRightAction} from '../move-to-actions'

interface GroupMenuProps {
  name: string
  isColumn?: boolean
  open: boolean
  setOpen: (open: boolean) => void
  /** Callback to be called when the group is renamed */
  onRename?: () => void
  onEditDetails?: () => void
  onEditLimit?: () => void
  onHide?: () => void
  onDelete?: () => void
  onMoveToLeft?: () => void
  onMoveToRight?: () => void
  moveToLeftDisabled?: boolean
  moveToRightDisabled?: boolean
  isSingleSelect?: boolean
  /** The list of items belonging to this column */
  items: ReadonlyArray<MemexItemModel>
}

const contextTriggerSx = {position: 'sticky', right: 0, mr: 1}

export const GroupMenu = ({
  name,
  isColumn = false,
  open,
  setOpen,
  onRename,
  onEditLimit,
  onEditDetails,
  onHide,
  onDelete,
  onMoveToLeft,
  onMoveToRight,
  moveToLeftDisabled,
  moveToRightDisabled,
  isSingleSelect,
  items,
}: GroupMenuProps) => {
  const {hasWritePermissions} = ViewerPrivileges()
  const nonRedactedItems = useMemo(() => items.filter(item => item.contentType !== ItemType.RedactedItem), [items])
  const menuButtonRef = useRef<HTMLButtonElement>(null)
  const {memex_column_menu_position} = useEnabledFeatures()

  const {openArchiveConfirmationDialog} = useArchiveMemexItemsWithConfirmation()
  const {openRemoveConfirmationDialog} = useRemoveMemexItemWithConfirmation()

  const onArchiveAll = useCallback(() => {
    if (items.length === 0) return
    const itemIds = items.map(item => item.id)
    openArchiveConfirmationDialog(
      itemIds,
      BoardColumnActionMenuUI,
      Resources.archiveGroupItemsConfirmationTitle,
      Resources.archiveGroupItemsConfirmationMessage(items.length),
    )
  }, [openArchiveConfirmationDialog, items])

  const onDeleteAll = useCallback(() => {
    if (items.length === 0) return
    const itemIds = items.map(item => item.id)
    openRemoveConfirmationDialog(itemIds, BoardColumnActionMenuUI, {
      title: Resources.deleteGroupItemsConfirmationTitle,
      content: Resources.deleteGroupItemsConfirmationMessage(items.length),
    })
  }, [openRemoveConfirmationDialog, items])

  const toggleMenu = useCallback(() => {
    setOpen(!open)
  }, [open, setOpen])
  const closeMenu = useCallback(() => {
    if (open) {
      setOpen(false)
    }
  }, [open, setOpen])

  const groupActions = []

  if (onRename && hasWritePermissions) {
    groupActions.push(<RenameGroupAction onSelect={onRename} key="rename" />)
  }
  if (onEditLimit && hasWritePermissions) {
    groupActions.push(<EditGroupLimitAction onSelect={onEditLimit} key="editLimit" />)
  }
  if (onEditDetails && hasWritePermissions) {
    groupActions.push(<EditGroupDetailsAction onSelect={onEditDetails} key="editDetails" />)
  }
  if (onHide) {
    groupActions.push(<HideGroupAction onSelect={onHide} key="hide" />)
  }
  if (onDelete && hasWritePermissions) {
    groupActions.push(<DeleteGroupAction onSelect={onDelete} key="delete" />)
  }

  const itemActions = []

  if (hasWritePermissions) {
    itemActions.push(
      <ArchiveItemsAction disabled={nonRedactedItems.length === 0} onSelect={onArchiveAll} key="archiveItems" />,
    )
    itemActions.push(
      <DeleteItemsAction disabled={nonRedactedItems.length === 0} onSelect={onDeleteAll} key="deleteItems" />,
    )
  }

  const positionActions = []

  if (memex_column_menu_position && onMoveToLeft && hasWritePermissions) {
    const isDisabled = moveToLeftDisabled || !isSingleSelect

    positionActions.push(
      <MoveToLeftAction
        disabled={isDisabled}
        isLeftmostColumn={isSingleSelect && moveToLeftDisabled}
        columnMoveNotAvailable={isSingleSelect === false ? 'iterations' : undefined}
        onSelect={onMoveToLeft}
        key="moveToLeft"
      />,
    )
  }
  if (memex_column_menu_position && onMoveToRight && hasWritePermissions) {
    const isDisabled = moveToRightDisabled || !isSingleSelect

    positionActions.push(
      <MoveToRightAction
        disabled={isDisabled}
        isRightmostColumn={isSingleSelect && moveToRightDisabled}
        columnMoveNotAvailable={isSingleSelect === false ? 'iterations' : undefined}
        onSelect={onMoveToRight}
        key="moveToRight"
      />,
    )
  }

  if (itemActions.length === 0 && groupActions.length === 0 && positionActions.length === 0) return null

  return (
    <ActionMenu open={open}>
      <ActionMenu.Anchor>
        <IconButton
          ref={menuButtonRef}
          aria-label={Resources.groupHeaderMenu(name, isColumn)}
          aria-haspopup="menu"
          variant="invisible"
          icon={KebabHorizontalIcon}
          size="small"
          sx={contextTriggerSx}
          onClick={toggleMenu}
          onKeyDown={event => {
            // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
            if (event.key === 'Enter' || event.code === 'Space') {
              event.preventDefault()
              toggleMenu()
            }
          }}
        />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay align="end" onClickOutside={closeMenu} onEscape={closeMenu}>
        <ActionList role="menu">
          {itemActions.length > 0 && (
            <ActionList.Group>
              <ActionList.GroupHeading>Items</ActionList.GroupHeading>
              {itemActions}
            </ActionList.Group>
          )}
          {groupActions.length > 0 && (
            <>
              {itemActions.length > 0 && <ActionList.Divider />}
              <ActionList.Group>
                <ActionList.GroupHeading>{isColumn ? 'Column' : 'Group'}</ActionList.GroupHeading>
                {groupActions}
              </ActionList.Group>
            </>
          )}
          {positionActions.length > 0 && (
            <>
              <ActionList.Divider />
              <ActionList.Group>
                <ActionList.GroupHeading>Position</ActionList.GroupHeading>
                {positionActions}
              </ActionList.Group>
            </>
          )}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

const RenameGroupAction = (props: ActionListItemProps) => (
  <ActionList.Item {...props}>
    <ActionList.LeadingVisual>
      <PencilIcon />
    </ActionList.LeadingVisual>
    Rename
  </ActionList.Item>
)

const EditGroupLimitAction = (props: ActionListItemProps) => (
  <ActionList.Item {...props}>
    <ActionList.LeadingVisual>
      <NumberIcon />
    </ActionList.LeadingVisual>
    Set limit
  </ActionList.Item>
)

const EditGroupDetailsAction = (props: ActionListItemProps) => (
  <ActionList.Item {...props}>
    <ActionList.LeadingVisual>
      <PencilIcon />
    </ActionList.LeadingVisual>
    Edit details
  </ActionList.Item>
)

const HideGroupAction = (props: ActionListItemProps) => (
  <ActionList.Item {...props}>
    <ActionList.LeadingVisual>
      <EyeClosedIcon />
    </ActionList.LeadingVisual>
    Hide from view
  </ActionList.Item>
)

const DeleteGroupAction = (props: ActionListItemProps) => (
  <ActionList.Item variant="danger" {...props}>
    <ActionList.LeadingVisual>
      <TrashIcon />
    </ActionList.LeadingVisual>
    Delete
  </ActionList.Item>
)

const ArchiveItemsAction = (props: ActionListItemProps) => (
  <ActionList.Item {...props}>
    <ActionList.LeadingVisual>
      <ArchiveIcon />
    </ActionList.LeadingVisual>
    Archive all
  </ActionList.Item>
)

const DeleteItemsAction = (props: ActionListItemProps) => (
  <ActionList.Item variant="danger" {...props}>
    <ActionList.LeadingVisual>
      <TrashIcon />
    </ActionList.LeadingVisual>
    Delete all
  </ActionList.Item>
)
