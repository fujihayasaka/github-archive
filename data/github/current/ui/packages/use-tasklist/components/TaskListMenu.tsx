import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {
  ChevronDownIcon,
  ChevronUpIcon,
  IssueOpenedIcon,
  IssueTracksIcon,
  KebabHorizontalIcon,
} from '@primer/octicons-react'
import {LABELS} from '../constants/labels'
import {useDragAndDrop} from '@github-ui/drag-and-drop'
import {useState} from 'react'
import type {TaskItem} from '../constants/types'

export type TaskListMenuProps = {
  onConvertToIssue?: (task: TaskItem, setIsConverting: (converting: boolean) => void) => void
  onConvertToSubIssue?: (task: TaskItem, setIsConverting: (converting: boolean) => void) => void
  totalItems: number
  item: TaskItem
  disabled?: boolean
  allowIssueConversion: boolean
  allowSubIssueConversion: boolean
  'data-testid'?: string
  setIsConverting: React.Dispatch<React.SetStateAction<boolean>>
  allowReordering?: boolean
}

type HandleMoveProps = {
  moveAction: string
  e: React.MouseEvent<HTMLLIElement> | React.KeyboardEvent<HTMLLIElement>
}

type HandleKeyDownProps = {
  e: React.KeyboardEvent<HTMLLIElement>
  move?: string
  convertToIssue?: boolean
  convertToSubIssue?: boolean
}

export const TaskListMenu = ({
  totalItems,
  onConvertToIssue,
  onConvertToSubIssue,
  item,
  allowIssueConversion,
  allowSubIssueConversion,
  disabled,
  setIsConverting,
  allowReordering,
  ...props
}: TaskListMenuProps) => {
  const {title, index} = item
  const {moveToPosition} = useDragAndDrop()
  const [openOverlay, setOpenOverlay] = useState(false)

  const handleMove = ({moveAction, e}: HandleMoveProps) => {
    e.preventDefault()
    e.stopPropagation()
    setOpenOverlay(false)

    switch (moveAction) {
      case 'up':
        moveToPosition(index, index - 1, true)
        break
      case 'down':
        moveToPosition(index, index + 1, false)
        break
      default:
        break
    }
  }

  const handleKeyDown = ({e, move, convertToIssue, convertToSubIssue}: HandleKeyDownProps) => {
    e.preventDefault()
    e.stopPropagation()

    if (e.code === 'Enter' && move) handleMove({moveAction: move, e})
    if (e.code === 'Enter' && convertToIssue) {
      setOpenOverlay(false)
      onConvertToIssue?.(item, setIsConverting)
    }

    if (e.code === 'Enter' && convertToSubIssue) {
      setOpenOverlay(false)
      onConvertToSubIssue?.(item, setIsConverting)
    }

    if (e.code === 'Escape') setOpenOverlay(false)
  }

  return (
    <ActionMenu open={openOverlay} onOpenChange={setOpenOverlay}>
      <ActionMenu.Anchor>
        <IconButton
          data-testid={props['data-testid']}
          icon={KebabHorizontalIcon}
          variant="invisible"
          aria-label={LABELS.openTaskOptions(title)}
          disabled={disabled}
          sx={{width: '24px', height: '24px', ':disabled': {background: 'none', cursor: 'inherit'}}}
        />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay>
        <ActionList>
          {allowReordering && (
            <>
              <ActionList.Item
                onClick={e => handleMove({moveAction: 'up', e})}
                onKeyDown={e => handleKeyDown({e, move: 'up'})}
                disabled={index === 0}
              >
                <ActionList.LeadingVisual>
                  <ChevronUpIcon />
                </ActionList.LeadingVisual>
                {LABELS.moveUp}
              </ActionList.Item>
              <ActionList.Item
                onClick={e => handleMove({moveAction: 'down', e})}
                onKeyDown={e => handleKeyDown({e, move: 'down'})}
                disabled={index === totalItems - 1}
              >
                <ActionList.LeadingVisual>
                  <ChevronDownIcon />
                </ActionList.LeadingVisual>
                {LABELS.moveDown}
              </ActionList.Item>
            </>
          )}

          {allowIssueConversion && onConvertToIssue && (
            <ActionList.Item
              onClick={() => onConvertToIssue?.(item, setIsConverting)}
              onKeyDown={e => handleKeyDown({e, convertToIssue: true})}
              data-testid={props['data-testid'] && `${props['data-testid']}-convert`}
            >
              <ActionList.LeadingVisual>
                <IssueOpenedIcon />
              </ActionList.LeadingVisual>
              {LABELS.convertToIssue}
            </ActionList.Item>
          )}
          {allowSubIssueConversion && onConvertToSubIssue && (
            <ActionList.Item
              onClick={() => onConvertToSubIssue?.(item, setIsConverting)}
              onKeyDown={e => handleKeyDown({e, convertToSubIssue: true})}
              data-testid={props['data-testid'] && `${props['data-testid']}-convert-sub-issue`}
            >
              <ActionList.LeadingVisual>
                <IssueTracksIcon />
              </ActionList.LeadingVisual>
              {LABELS.convertToSubIssue}
            </ActionList.Item>
          )}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
