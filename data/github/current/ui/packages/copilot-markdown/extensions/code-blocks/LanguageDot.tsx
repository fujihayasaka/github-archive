import styles from './LanguageDot.module.css'

interface LanguageDotProps {
  color: string | undefined
}

export function LanguageDot({color}: LanguageDotProps) {
  return <span style={{backgroundColor: color}} className={styles.languageDot} />
}
