import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {CopilotLicenseType} from '@github-ui/copilot-chat/utils/copilot-chat-types'

import styles from '../ChatInputBanners.module.css'
import {EditorUpsellBanner} from '../EditorUpsellBanner'
import {ProPlusSuccessBanner, useProPlusSuccessBannerVisibility} from '../ProPlusSuccessBanner'
import {TrialSuccessBanner, useTrialSuccessBannerVisibility} from '../TrialSuccessBanner'

export function NewConversationBanners() {
  const licenseType = useEntitlement().licenseType
  const trialSuccessVisibility = useTrialSuccessBannerVisibility()
  const proPlusSuccessVisibility = useProPlusSuccessBannerVisibility()

  const showProPlusBanner = proPlusSuccessVisibility.visible
  const showTrialBanner =
    !showProPlusBanner && trialSuccessVisibility.visible && licenseType === CopilotLicenseType.LicensedFull
  const showEditorUpsell = !showProPlusBanner && !showTrialBanner

  return (
    <>
      {showEditorUpsell && <EditorUpsellBanner />}

      {showTrialBanner && <TrialSuccessBanner className={styles.banner} onDismiss={trialSuccessVisibility.onDismiss} />}

      {showProPlusBanner && (
        <ProPlusSuccessBanner className={styles.banner} onDismiss={proPlusSuccessVisibility.onDismiss} />
      )}
    </>
  )
}
