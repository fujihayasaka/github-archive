import styles from './empty-column-sash.module.css'

/**
 * This component is used as a placeholder when the user is hovering a card
 * over an empty column to indicate to the user where this will be added if
 * the card were to be dropped.
 */
export const EmptyColumnSash: React.FC = () => <div className={styles.Box} />
