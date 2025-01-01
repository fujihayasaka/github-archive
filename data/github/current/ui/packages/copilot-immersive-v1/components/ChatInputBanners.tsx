import {AmbientErrorBanner} from '@github-ui/copilot-chat/components/AmbientErrorBanner'
import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {useChatState, useChatStateLens} from '@github-ui/copilot-chat/CopilotChatContext'
import {CopilotLicenseType} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'

import styles from './ChatInputBanners.module.css'
import {EditorUpsellBanner} from './EditorUpsellBanner'
import {QuotaMeterBanner, useQuotaMeterBannerVisibility} from './Quota/QuotaMeterBanner'
import {TopicIndicator, useCurrentTopic} from './TopicIndicator'
import {TrialSuccessBanner, useTrialSuccessBannerVisibility} from './TrialSuccessBanner'

export function ChatInputBanners() {
  const isThreadSelected = useChatStateLens(s => s.selectedThreadID !== null)
  const {ambientError} = useChatState()
  const licenseType = useEntitlement().licenseType

  const quotaVisibility = useQuotaMeterBannerVisibility()
  const trialSuccessVisibility = useTrialSuccessBannerVisibility()
  const topic = useCurrentTopic()
  const showAmbientErrorBanner = copilotFeatureFlags.ambientErrorBanner && ambientError

  return (
    <>
      {!quotaVisibility.visible &&
        !showAmbientErrorBanner &&
        !trialSuccessVisibility.visible &&
        !topic &&
        !isThreadSelected && <EditorUpsellBanner />}
      {quotaVisibility.visible && <QuotaMeterBanner className={styles.banner} onDismiss={quotaVisibility.onDismiss} />}
      {showAmbientErrorBanner && <AmbientErrorBanner ambientError={ambientError} useLargerBorderRadius />}
      {trialSuccessVisibility.visible && licenseType === CopilotLicenseType.LicensedFull && (
        <TrialSuccessBanner className={styles.banner} onDismiss={trialSuccessVisibility.onDismiss} />
      )}
      {topic && <TopicIndicator topic={topic} />}
    </>
  )
}
