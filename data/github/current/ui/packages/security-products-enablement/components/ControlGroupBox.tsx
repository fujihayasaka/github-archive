import {Label} from '@primer/react'

import styles from './ControlGroupBox.module.css'

type ControlGroupBoxProps = {
  children: React.ReactNode
  title: string
  showGHASLabel: boolean
}

const ControlGroupBox = ({children, title, showGHASLabel}: ControlGroupBoxProps) => {
  return (
    <div className={styles.Box}>
      <div className={styles.Box_1}>
        <strong className={styles.Text}>{title}</strong> {showGHASLabel && <Label>GitHub Advanced Security</Label>}
      </div>
      {children}
    </div>
  )
}

export default ControlGroupBox
