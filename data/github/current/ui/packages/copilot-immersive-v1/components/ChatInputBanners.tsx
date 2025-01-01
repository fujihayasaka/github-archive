import {AmbientErrorBanner} from '@github-ui/copilot-chat/components/AmbientErrorBanner'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'

import styles from './ChatInputBanners.module.css'
import {QuotaExceededBanner, useQuotaExceededBannerVisibility} from './Quota/QuotaExceededBanner'
import {QuotaMeterBanner, useQuotaMeterBannerVisibility} from './Quota/QuotaMeterBanner'

export function ChatInputBanners() {
  const {ambientError} = useChatState()

  const quotaVisibility = useQuotaMeterBannerVisibility()
  const quotaExceededVisibility = useQuotaExceededBannerVisibility()

  return (
    <>
      {ambientError && <AmbientErrorBanner ambientError={ambientError} useLargerBorderRadius />}

      {quotaExceededVisibility.visible && <QuotaExceededBanner onDismiss={quotaExceededVisibility.onDismiss} />}
      {quotaVisibility.visible && <QuotaMeterBanner className={styles.banner} onDismiss={quotaVisibility.onDismiss} />}
    </>
  )
}
