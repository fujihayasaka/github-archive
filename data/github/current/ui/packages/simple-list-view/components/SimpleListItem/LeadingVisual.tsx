import styles from './LeadingVisual.module.css'

type LeadingVisualProps = {
  children: React.ReactNode
}

const LeadingVisual = ({children}: LeadingVisualProps) => (
  <div className={styles.container}>
    <div>{children}</div>
  </div>
)
LeadingVisual.displayName = 'LeadingVisualProps'

export default LeadingVisual
