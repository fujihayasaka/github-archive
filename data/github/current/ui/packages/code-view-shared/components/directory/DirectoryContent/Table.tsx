import type React from 'react'

import styles from './Table.module.css'
import {clsx} from 'clsx'

/**
 * Table Frame component
 * @param as - Use `ul` only when all children are `li` items, otherwise add a nested `ul` at your convenience.
 */
export function Table({children, className, ...props}: React.PropsWithChildren<{className?: string}>) {
  return (
    <table className={clsx(styles.Box, className)} {...props}>
      {children}
    </table>
  )
}

export const HeaderRow: React.FC<{children: React.ReactNode; className?: string}> = ({children, className}) => {
  return (
    <thead className={clsx(className, styles.Box_1)}>
      <tr className={styles.Box_2}>{children}</tr>
    </thead>
  )
}

interface RowClickProps {
  onClick?: React.MouseEventHandler<HTMLTableRowElement>
  index?: number
  id?: string
}

export const Row: React.FC<React.PropsWithChildren<RowClickProps>> = ({children, onClick, index, id}) => {
  return (
    <tr onClick={onClick} data-index={index} id={id} className={styles.Box_3}>
      {children}
    </tr>
  )
}

export const TableFooter: React.FC<{children: React.ReactNode}> = ({children}) => {
  return <tfoot className={styles.Box_4}>{children}</tfoot>
}
