import {LightBulbIcon} from '@primer/octicons-react'

import styles from './Tip.module.css'

interface TipProps {
  children: string
}

export function Tip({children}: TipProps) {
  return (
    <div className={styles.container}>
      <div className={styles.prefix}>
        <LightBulbIcon />
        Tip
      </div>
      {children}
    </div>
  )
}
