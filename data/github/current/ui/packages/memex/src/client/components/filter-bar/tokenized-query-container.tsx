import styles from './tokenized-query-container.module.css'

/**
 * Div with styles that is intended to wrap the TokenizedQuery and RawFilterInput components.
 */
export function TokenizedQueryContainer({children}: React.PropsWithChildren) {
  return <div className={styles.Box}>{children}</div>
}
