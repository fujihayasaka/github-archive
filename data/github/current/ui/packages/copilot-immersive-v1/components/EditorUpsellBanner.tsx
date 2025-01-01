import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {useChatStateValue} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {EditorMenu} from '@github-ui/global-copilot-menu/EditorMenu'
import {EditorMenuItems, recordMenuClick} from '@github-ui/global-copilot-menu/EditorMenuItems'
import editors from '@github-ui/global-copilot-menu/editors'
import {sendEvent} from '@github-ui/hydro-analytics'
import {TriangleDownIcon, XIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, ButtonGroup, IconButton, LinkButton} from '@primer/react'
import {useId} from 'react'

import styles from './EditorUpsellBanner.module.css'

export function EditorUpsellBanner() {
  const isDismissed = useChatStateValue('isEditorUpsellBannerDismissed')
  const chatManager = useChatManager()
  const {isLicensedLimited} = useEntitlement()
  const titleId = useId()

  const analyticsMenuLocation = 'editor_upsell_banner'

  const handleClick = (eventName: string, action: string) => {
    if (copilotFeatureFlags.freeToPaidTelemetry) {
      recordMenuClick({eventName, menuLocation: analyticsMenuLocation, mode: 'immersive', action})
    } else {
      sendEvent('dotcom_chat.activate', {
        target: `EDITOR_UPSELL_BANNER_${eventName.toUpperCase()}`,
        mode: 'immersive',
      })
    }
  }

  if (isDismissed || !isLicensedLimited) return null

  return (
    <div className={styles.container}>
      <section className={styles.banner} aria-labelledby={titleId}>
        <h2 className={styles.title} id={titleId}>
          Install Copilot in your favorite code editor
        </h2>
        <p className={styles.description}>Copilot is available for a multitude of editors to fit your needs</p>
        {copilotFeatureFlags.freeToPaidSettingsUpgrade ? (
          <EditorMenu menuLocation={analyticsMenuLocation} mode="immersive" />
        ) : (
          <ButtonGroup className={styles.actions}>
            <LinkButton
              className={styles.editorButton}
              href={editors.vscode.url}
              leadingVisual={<img src={editors.vscode.icon} alt="" height="20" width="20" />}
              onClick={() => {
                handleClick('vscode', 'ide_menu_primary_button_click')
              }}
            >
              {editors.vscode.name}
            </LinkButton>
            <ActionMenu>
              <ActionMenu.Anchor>
                {/* Tooltip breaks ButtonGroup: https://github.com/primer/react/issues/4129 */}
                {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
                <IconButton
                  aria-label="More editors"
                  icon={TriangleDownIcon}
                  unsafeDisableTooltip
                  onClick={() => {
                    handleClick('menu', 'ide_menu_open')
                  }}
                />
              </ActionMenu.Anchor>

              <ActionMenu.Overlay align="end">
                <ActionList>
                  <EditorMenuItems menuLocation={analyticsMenuLocation} mode={'immersive'} />
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          </ButtonGroup>
        )}
        <IconButton
          variant="invisible"
          className={styles.closeButton}
          icon={XIcon}
          aria-label="Dismiss banner"
          onClick={() => {
            chatManager.dismissEditorUpsellBanner()

            sendEvent('dotcom_chat.activate', {
              target: 'EDITOR_UPSELL_BANNER_DISMISS',
              mode: 'immersive',
            })
          }}
        />
      </section>
    </div>
  )
}
