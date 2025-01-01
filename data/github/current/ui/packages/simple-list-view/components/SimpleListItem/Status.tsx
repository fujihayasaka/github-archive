import {type Label, Stack, type StackProps} from '@primer/react'
import type {ElementType, ReactElement} from 'react'

import itemContainerStyles from './ItemContainer.module.css'

export type StatusProps = {
  statusStyling?: StackProps<ElementType>
  children: ReactElement<typeof Label> | Array<ReactElement<typeof Label>>
}

// eslint-disable-next-line @eslint-react/no-unstable-default-props
const Status = ({statusStyling = {}, children}: StatusProps) => {
  const {direction, gap, ...rest} = statusStyling

  return (
    <Stack
      className={itemContainerStyles.status}
      direction={direction || 'horizontal'}
      gap={gap || 'condensed'}
      wrap={'wrap'}
      {...rest}
    >
      {children}
    </Stack>
  )
}
Status.displayName = 'Status'

export default Status
