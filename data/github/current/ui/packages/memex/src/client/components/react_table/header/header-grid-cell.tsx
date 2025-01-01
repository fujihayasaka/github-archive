import {Box, type BoxProps} from '@primer/react'
import {clsx} from 'clsx'
import {forwardRef} from 'react'

import styles from './header-grid-cell.module.css'

export const HeaderGridCell = forwardRef<HTMLDivElement, BoxProps>((props, ref) => {
  const {sx, className, ...other} = props

  return (
    <Box ref={ref} role="columnheader" aria-colspan={1} sx={sx} className={clsx(className, styles.Box)} {...other} />
  )
})

HeaderGridCell.displayName = 'HeaderGridCell'
