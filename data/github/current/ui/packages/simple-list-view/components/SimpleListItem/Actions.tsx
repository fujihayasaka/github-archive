import {Stack, type StackProps} from '@primer/react'
import {clsx} from 'clsx'
import type {ElementType} from 'react'

import styles from './Actions.module.css'
import itemContainerStyles from './ItemContainer.module.css'

type ActionsProp = {
  actionStyling?: StackProps<ElementType>
  children: React.ReactNode
}

// eslint-disable-next-line @eslint-react/no-unstable-default-props
export const Actions = ({actionStyling = {}, children}: ActionsProp) => {
  const {direction, gap, ...rest} = actionStyling
  return (
    <Stack
      className={clsx(styles.container, itemContainerStyles.actions)}
      direction={direction || 'horizontal'}
      gap={gap || 'condensed'}
      {...rest}
    >
      {children}
    </Stack>
  )
}
Actions.displayName = 'Actions'
