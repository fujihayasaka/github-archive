import {Octicon} from '@primer/react/deprecated'
import type {PropsWithChildren} from 'react'
import {ChevronDownIcon} from '@primer/octicons-react'

import styles from './MobileTitleNavigationButton.module.css'

type MobileTitleNavigationButtonProps = {
  onClick: () => void
}

export default function MobileTitleNavigationButton(props: PropsWithChildren<MobileTitleNavigationButtonProps>) {
  const {children, onClick} = props
  return (
    <button onClick={onClick} className={styles.Box}>
      <div className={styles.Box_1}>{children}</div>
      <Octicon icon={ChevronDownIcon} size={16} className={styles.Octicon} />
    </button>
  )
}
