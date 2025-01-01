import type {PropsWithChildren} from 'react'
import type React from 'react'
import styles from './NestingTable.module.css'

interface NestingTableProps extends PropsWithChildren {
  header: React.ReactNode
}

export function NestingTable({header, children, ...rest}: NestingTableProps) {
  return (
    <div className={styles.container} {...rest}>
      <div className={styles.header}>{header}</div>
      <div className={styles.body}>{children}</div>
    </div>
  )
}
