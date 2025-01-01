import {ArrowUpRightIcon} from '@primer/octicons-react'
import styles from './PlaygroundCard.module.css'
import type React from 'react'
import {testIdProps} from '@github-ui/test-id-props'

export function PlaygroundCard({
  sample,
  onAction,
  size = 'small',
}: {
  sample: string
  onAction: (e: React.MouseEvent<HTMLDivElement> | React.KeyboardEvent<HTMLDivElement>) => void
  size?: 'small' | 'large'
}) {
  function handleOnKeyPress(event: React.KeyboardEvent<HTMLDivElement>) {
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if (event.key === 'Enter') {
      onAction(event)
    }
  }

  return (
    <div
      role="button"
      tabIndex={0}
      onKeyDown={handleOnKeyPress}
      onClick={onAction}
      className={`${styles.playgroundCard} ${styles[size]}`}
      {...testIdProps('playground-card')}
    >
      <div className={styles.sampleContainer}>{sample}</div>
      <div className={styles.chevronContainer}>
        <ArrowUpRightIcon />
      </div>
    </div>
  )
}
