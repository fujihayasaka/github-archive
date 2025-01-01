import {Box, type BoxProps} from '@primer/react'
import {clsx} from 'clsx'
import {forwardRef} from 'react'

import {useTableCellHeight} from '../table-provider'
import styles from './base-cell.module.css'

type BaseCellProps = BoxProps & {
  editing?: boolean
  disallowSelection?: boolean
}

export const BaseCell = forwardRef<HTMLDivElement, BaseCellProps>((props, ref) => {
  const {sx, editing, disallowSelection, className, style, ...other} = props
  const cellHeight = useTableCellHeight()

  return (
    <Box
      ref={ref}
      sx={sx}
      style={{
        height: `${cellHeight}px`,
        userSelect: disallowSelection ? 'none' : 'auto',
        ...style,
      }}
      className={clsx(className, styles.Box, editing && styles.Box_1)}
      {...other}
    />
  )
})

BaseCell.displayName = 'BaseCell'
