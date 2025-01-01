import {clsx} from 'clsx'
import {type ReactElement, type ReactNode, useId} from 'react'

import {LabelIdProvider} from '../LabelIdContext'
import styles from './ItemContainer.module.css'

export type ContainerProps = {
  disabled?: boolean
  children: ReactNode
}

const Container = ({disabled = false, children}: ContainerProps) => {
  const labelId = useId()

  return (
    <LabelIdProvider value={labelId}>
      <li
        aria-labelledby={labelId}
        className={clsx('controlBoxContainer', styles.container, disabled && styles.disabled)}
      >
        <div className={styles.contents}>{children}</div>
      </li>
    </LabelIdProvider>
  )
}

export default Container
