import {forwardRef} from 'react'

import styles from './filter-input-container.module.css'

export const FilterInputContainer = forwardRef<HTMLDivElement, {children: React.ReactNode}>(
  function FilterInputContainer({children}, forwardedRef) {
    return (
      <div ref={forwardedRef} className={styles.Box}>
        {children}
      </div>
    )
  },
)
