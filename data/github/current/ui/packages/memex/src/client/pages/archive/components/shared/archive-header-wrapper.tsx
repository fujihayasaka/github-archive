import styles from './archive-header-wrapper.module.css'

export function ArchiveHeaderWrapper({children}: {children: React.ReactNode}) {
  return (
    <div className={styles.Box}>
      <div className={styles.Box_1}>{children}</div>
    </div>
  )
}
