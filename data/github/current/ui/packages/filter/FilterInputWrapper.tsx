import {testIdProps} from '@github-ui/test-id-props'
import type {PropsWithChildren} from 'react'

import styles from './FilterInputWrapper.module.css'

type FilterInputWrapperProps = PropsWithChildren & {
  isStandalone?: boolean
}
export const FilterInputWrapper = ({children, isStandalone = false}: FilterInputWrapperProps) => {
  if (isStandalone) {
    return (
      <div {...testIdProps('filter-bar')} className={styles.Box_0}>
        {children}
      </div>
    )
  }
  return (
    <div {...testIdProps('filter-bar')} className={styles.Box_1}>
      {children}
    </div>
  )
}
