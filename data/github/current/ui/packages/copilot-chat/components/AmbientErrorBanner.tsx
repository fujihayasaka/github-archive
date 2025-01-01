import {Banner} from '@primer/react/experimental'

import type {AmbientError} from '../utils/copilot-chat-reducer'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import styles from './AmbientErrorBanner.module.css'

export function AmbientErrorBanner({
  ambientError,
  useLargerBorderRadius = false,
}: {
  ambientError: AmbientError
  useLargerBorderRadius?: boolean
}) {
  const chatManager = useChatManager()
  const borderRadiusClass = useLargerBorderRadius ? styles.largeBorderRadius : styles.mediumBorderRadius
  return (
    <Banner
      className={`${styles.ambientErrorBanner} ${borderRadiusClass}`}
      description={ambientError.message}
      variant="warning"
      title="Error during copilot chat has occurred."
      hideTitle
      onDismiss={() => {
        chatManager.dismissAmbientError()
      }}
    />
  )
}
