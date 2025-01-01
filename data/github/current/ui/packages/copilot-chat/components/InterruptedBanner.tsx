import {Banner} from '@primer/react/experimental'
import {clsx} from 'clsx'

import styles from './InterruptedBanner.module.css'

export function InterruptedBanner({messageHasContent}: {messageHasContent?: boolean}) {
  return (
    <Banner
      className={clsx(styles.interruptedBanner, messageHasContent && styles.hasContent)}
      data-testid="chat-message-interrupted"
      description="Copilot was interrupted before it could finish this message."
      hideTitle
      title="Message interrupted"
      variant="info"
    />
  )
}
