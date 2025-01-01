import {useLabelId} from '../LabelIdContext'
import styles from './Items.module.css'

export const Items = ({children}: {children: React.ReactNode}) => {
  const labelId = useLabelId()

  return (
    <ul aria-labelledby={labelId} className={styles.list}>
      {children}
    </ul>
  )
}
