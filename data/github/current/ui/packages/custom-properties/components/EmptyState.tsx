import type React from 'react'

import styles from './EmptyState.module.css'

export function EmptyState({children}: React.PropsWithChildren) {
  return (
    <div className={styles.EmptyStateContainer}>
      <strong>{children}</strong>
    </div>
  )
}
