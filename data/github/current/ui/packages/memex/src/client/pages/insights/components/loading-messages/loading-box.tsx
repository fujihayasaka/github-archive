import styles from './loading-box.module.css'

// LoadingBox is the styled Box component to be used for all loading messages.
export const LoadingBox = ({children}: {children: React.ReactNode}) => {
  return <div className={styles.Box}>{children}</div>
}
