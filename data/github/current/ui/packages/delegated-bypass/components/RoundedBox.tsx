import type {ReactNode} from 'react'
import styles from './RoundedBox.module.css'

type RoundedBoxProps = {
  className?: string
  children: ReactNode
}
export function RoundedBox({className, children}: RoundedBoxProps) {
  return <div className={`Box ${className || ''} ${styles.roundedBox}`}>{children}</div>
}
