import type React from 'react'

import styles from './SettingsFormFooter.module.css'

type SettingsFormFooterProps = {
  children: React.ReactNode
}

const SettingsFormFooter: React.FC<SettingsFormFooterProps> = ({children}) => {
  return <div className={styles.Box}>{children}</div>
}

export default SettingsFormFooter
