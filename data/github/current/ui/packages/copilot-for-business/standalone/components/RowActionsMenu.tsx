import {KebabHorizontalIcon} from '@primer/octicons-react'
import {ActionMenu, IconButton, ActionList} from '@primer/react'
import {useRef} from 'react'

type Props = React.PropsWithChildren<{
  isVisible: boolean
  testId?: string
}>

export function RowActionsMenu(props: Props) {
  const {isVisible, testId} = props

  const returnFocusRef = useRef(null)

  if (!isVisible) {
    return null
  }

  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <IconButton
          icon={KebabHorizontalIcon}
          variant="invisible"
          aria-label="Open seat options"
          ref={returnFocusRef}
          data-testid={testId}
          sx={{height: '28px', width: '28px'}}
        />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay>
        <ActionList selectionVariant="single">{props.children}</ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
