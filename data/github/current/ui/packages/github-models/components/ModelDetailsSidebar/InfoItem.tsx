import type {PropsWithChildren} from 'react'
import styles from './InfoItem.module.css'

interface InfoItemProps extends PropsWithChildren {
  isInline: boolean
  label?: string
}

export function InfoItem({isInline = false, children, label, ...rest}: InfoItemProps) {
  return (
    <div className={styles.wrapper + (isInline ? ` ${styles.isInline}` : '')}>
      {label && <div className={styles.label}>{label}</div>}
      <div className="fgColor-muted" {...rest}>
        {children}
      </div>
    </div>
  )
}
