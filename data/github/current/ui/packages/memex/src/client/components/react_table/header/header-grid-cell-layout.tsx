import {Box, type BoxProps} from '@primer/react'
import {clsx} from 'clsx'
import {forwardRef} from 'react'

import styles from './header-grid-cell-layout.module.css'

export const HeaderGridCellLayout = forwardRef<HTMLDivElement, BoxProps>((props, ref) => {
  const {children, sx, className, ...otherProps} = props
  return (
    <Box sx={sx} ref={ref} className={clsx(className, styles.Box)} {...otherProps}>
      {children}
    </Box>
  )
})

HeaderGridCellLayout.displayName = 'HeaderGridCellLayout'
