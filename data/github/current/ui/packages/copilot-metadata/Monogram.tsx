import styles from './Monogram.module.css'

export const Monogram = ({initials}: {initials: string}) => {
  return <div className={styles.monogram}>{initials}</div>
}
