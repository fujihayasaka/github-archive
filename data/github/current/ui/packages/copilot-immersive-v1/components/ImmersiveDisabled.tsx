import CopilotIconAnimation from '@github-ui/copilot-chat/CopilotIconAnimation'
import {sendEvent} from '@github-ui/hydro-analytics'
import {LinkButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'

import styles from './ImmersiveDisabled.module.css'

export function ImmersiveDisabled() {
  return (
    <div className={styles.container}>
      <div className={styles.content}>
        <CopilotIconAnimation />
      </div>
      <div className={styles.footer}>
        <div className={styles.bannerContainer}>
          <Banner
            variant="upsell"
            title="Copilot is disabled"
            hideTitle
            description="Copilot on GitHub is currently disabled by your organization."
            primaryAction={
              <LinkButton
                as="a"
                href="https://github.com/settings/copilot"
                onClick={() =>
                  sendEvent('dotcom_chat.activate', {target: 'NO_ACCESS_SETTING_DISABLED', mode: 'immersive'})
                }
              >
                Settings
              </LinkButton>
            }
          />
        </div>
      </div>
    </div>
  )
}
