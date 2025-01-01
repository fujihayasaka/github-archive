import {ArrowLeftIcon, ArrowRightIcon} from '@primer/octicons-react'
import {ActionList, type ActionListItemProps} from '@primer/react'

interface MoveToActionsProps {
  columnMoveNotAvailable?: string
}

interface MoveToLeftActionProps extends MoveToActionsProps {
  isLeftmostColumn?: boolean
}

export const MoveToLeftAction = ({
  isLeftmostColumn,
  columnMoveNotAvailable,
  ...props
}: ActionListItemProps & MoveToLeftActionProps) => (
  <ActionList.Item inactiveText={isLeftmostColumn ? 'This is the left-most column' : undefined} {...props}>
    <ActionList.LeadingVisual>
      <ArrowLeftIcon />
    </ActionList.LeadingVisual>
    Move left
    {columnMoveNotAvailable && (
      <ActionList.Description variant="block">Unavailable for {columnMoveNotAvailable}</ActionList.Description>
    )}
  </ActionList.Item>
)

interface MoveToRightActionProps extends MoveToActionsProps {
  isRightmostColumn?: boolean
}

export const MoveToRightAction = ({
  isRightmostColumn,
  columnMoveNotAvailable,
  ...props
}: ActionListItemProps & MoveToRightActionProps) => (
  <ActionList.Item inactiveText={isRightmostColumn ? 'This is the right-most column' : undefined} {...props}>
    <ActionList.LeadingVisual>
      <ArrowRightIcon />
    </ActionList.LeadingVisual>
    Move right
    {columnMoveNotAvailable && (
      <ActionList.Description variant="block">Unavailable for {columnMoveNotAvailable}</ActionList.Description>
    )}
  </ActionList.Item>
)
