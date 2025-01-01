import styles from './UnreadIndicator.module.css'

type UnreadIndicatorProps = {
  unread?: boolean
}

export function UnreadIndicator({unread}: UnreadIndicatorProps) {
  return unread ? (
    <div className={styles.unread}>
      <span className="sr-only">New activity.</span>
    </div>
  ) : null
}
