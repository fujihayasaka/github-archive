import {type ReactNode, useId} from 'react'

import {LabelIdProvider} from '../LabelIdContext'
import styles from './SimpleListViewContainer.module.css'

type SimpleListViewContainerProps = {
  ['data-testid']?: string
  children: ReactNode
}

const SimpleListViewContainer = ({children, ...props}: SimpleListViewContainerProps) => {
  const labelId = useId()

  return (
    <LabelIdProvider value={labelId}>
      <div className={styles.container} {...props}>
        {children}
      </div>
    </LabelIdProvider>
  )
}

export default SimpleListViewContainer
