import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {ClockIcon} from '@primer/octicons-react'
import {RelativeTime} from '@primer/react'

import styles from './SpacesCard.module.css'

interface SpacesCardProps {
  copilotSpace: CustomCopilot
}

export function SpacesCard({copilotSpace}: SpacesCardProps) {
  const {name, description, updatedAt = new Date()} = copilotSpace

  return (
    <div className={styles.container}>
      <div className={styles.content}>
        <h3 className={styles.title}>{name}</h3>
        <p className={styles.description}>{description}</p>
        <div className={styles.metadata}>
          <div className={styles.metadataItem}>
            <ClockIcon className={styles.metadataIcon} />
            <RelativeTime format="micro" date={new Date(updatedAt)} />
          </div>
        </div>
      </div>
    </div>
  )
}
