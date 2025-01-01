import type {PropsWithChildren} from 'react'
import styles from './PromptLayout.module.css'

export function PromptLayout({children}: PropsWithChildren) {
  return <div className={styles.wrapper}>{children}</div>
}
