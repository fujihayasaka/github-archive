import styles from './ChecksStatusBadgeHeader.module.css'

export default function HeaderState({checksHeaderState}: {checksHeaderState: string}): JSX.Element {
  switch (checksHeaderState) {
    case 'SUCCEEDED':
      return <span className={styles.Text}>All checks have passed</span>
    case 'FAILED':
      return <span className={styles.Text_1}>All checks have failed</span>
    case 'PENDING':
      return <span className={styles.Text_2}>Some checks haven’t completed yet</span>
    default:
      return <span className={styles.Text_1}>Some checks were not successful</span>
  }
}
