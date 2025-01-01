import styles from './Section.module.css'

type SectionProps = {
  children: React.ReactNode
}

function Section({children}: SectionProps) {
  return <div className={styles.Box}>{children}</div>
}

export default Section
