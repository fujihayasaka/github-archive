import {AlertIcon} from '@primer/octicons-react'
import {testIdProps} from '@github-ui/test-id-props'
import styles from './MissingCombinationPlaceholder.module.css'
import {Heading} from '@primer/react'

export function MissingCombinationPlaceholder() {
  return (
    <div className={styles.placeholderContainer} {...testIdProps('missing-combination-placeholder')}>
      <div className="color-fg-attention">
        <AlertIcon size={16} />
      </div>
      <Heading as="h2" className={styles.documentationText}>
        Documentation for this language and SDK combination is unavailable
      </Heading>
      <p className={styles.differentComboText}>Try a different combination</p>
    </div>
  )
}
