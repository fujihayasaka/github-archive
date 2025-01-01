import styles from './styles.module.css'

export function SpaceFiller({height = 600}: {height?: number}) {
  return (
    <div style={{height}} className={styles.spacefiller}>
      This is just an empty space to cause some scroll for testing navigation focus and scroll restoration.
    </div>
  )
}
