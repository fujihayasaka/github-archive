import {Stack, type StackProps} from '@primer/react'
import type {ElementType} from 'react'

import itemContainerStyles from './ItemContainer.module.css'

type TrailingActionsProps = {
  children: React.ReactNode
  trailingActionStyling?: StackProps<ElementType>
}

// eslint-disable-next-line @eslint-react/no-unstable-default-props
export const TrailingActions = ({children, trailingActionStyling = {}}: TrailingActionsProps) => {
  const {direction, gap, ...rest} = trailingActionStyling
  return (
    <Stack
      className={itemContainerStyles.trailingActions}
      direction={direction || 'horizontal'}
      gap={gap || 'condensed'}
      {...rest}
    >
      {children}
    </Stack>
  )
}
TrailingActions.displayName = 'TrailingActions'
