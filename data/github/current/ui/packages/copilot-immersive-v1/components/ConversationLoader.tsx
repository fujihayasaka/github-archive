import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'

import styles from './ConversationLoader.module.css'

export function ConversationLoader() {
  return (
    <div className={styles.ConversationLoader} data-testid="conversation-loader">
      <div className={styles.ConversationLoader__userGroup}>
        <LoadingSkeleton variant="rounded" height="20px" width="random" />
      </div>
      <div className={styles.ConversationLoader__assistantGroup}>
        <LoadingSkeleton
          className={styles.ConversationLoader__assistantAvatar}
          variant="elliptical"
          sx={{position: 'absolute', height: 24}}
        />
        {Array.from({length: Math.floor(Math.random() * 4) + 2}).map((_, index) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <LoadingSkeleton variant="rounded" height="20px" width="random" key={index} />
        ))}
      </div>
    </div>
  )
}
