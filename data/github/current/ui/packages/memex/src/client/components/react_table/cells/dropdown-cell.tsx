import type {SxProp} from '@primer/react'
import {clsx} from 'clsx'
import {forwardRef} from 'react'

import {DropdownCaret} from '../../common/dropdown-caret'
import {BaseCell} from './base-cell'
import styles from './dropdown-cell.module.css'

export const DropdownCell = forwardRef<
  HTMLButtonElement,
  React.PropsWithChildren<SxProp> & {isDisabled?: boolean; className?: string}
>(({children, isDisabled, className}, ref) => {
  return (
    <BaseCell disallowSelection className={clsx(styles.BaseCell, className)}>
      {children}
      {isDisabled ? null : <DropdownCaret ref={ref} />}
    </BaseCell>
  )
})

DropdownCell.displayName = 'DropdownCell'
