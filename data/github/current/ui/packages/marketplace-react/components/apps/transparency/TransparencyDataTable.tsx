import styles from './transparency.module.css'
import React from 'react'
import {Text} from '@primer/react'

export type TransparencyDataTableProps = {
  items: Array<{
    label: string
    value?: React.ReactNode
  }>
}

export function TransparencyDataTable({items}: TransparencyDataTableProps) {
  return (
    <dl className={styles.transparencyDataTable}>
      {items.map(
        item =>
          item.value && (
            <React.Fragment key={item.label}>
              <dt>
                <Text size="small" weight="semibold">
                  {item.label}
                </Text>
              </dt>
              <dd>
                <Text size="small">{item.value}</Text>
              </dd>
            </React.Fragment>
          ),
      )}
    </dl>
  )
}
