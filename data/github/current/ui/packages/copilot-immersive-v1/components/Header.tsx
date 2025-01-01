import {ModelPicker} from '@github-ui/copilot-chat/components/ModelPicker'
import {threadName as getThreadName} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useChatStateLens} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {setTitle} from '@github-ui/document-metadata'
import {sendEvent} from '@github-ui/hydro-analytics'
import type {FeedbackRef} from '@github-ui/user-feedback'
import {UserFeedback} from '@github-ui/user-feedback'
import {CommentIcon, GearIcon, KebabHorizontalIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {useRef} from 'react'

import styles from './Header.module.css'
import {PreviewModelCapabilityWarning} from './PreviewModelCapabilityWarning'

export function Header() {
  const manager = useChatManager()
  const threadName = useChatStateLens(s => getThreadName(manager.getSelectedThread(s)))
  setTitle(
    copilotFeatureFlags.immersiveTitleFavicon ? `GitHub Copilot · ${threadName}` : `${threadName} · GitHub Copilot`,
  )
  const feedbackRef = useRef<FeedbackRef>(null)

  return (
    <div className={styles.header}>
      <div className={styles.centerControls}>
        <ModelPicker />
        <PreviewModelCapabilityWarning />
      </div>
      <div className={styles.rightControls}>
        <ActionMenu>
          <ActionMenu.Anchor>
            <IconButton
              icon={KebabHorizontalIcon}
              aria-label="Open menu"
              onClick={() => sendEvent('dotcom_chat.activate', {target: 'META_CONTEXT_MENU', mode: 'immersive'})}
            />
          </ActionMenu.Anchor>
          <ActionMenu.Overlay width="auto">
            <ActionList>
              <ActionList.Item
                onSelect={() => {
                  feedbackRef.current?.openDialog()
                  sendEvent('dotcom_chat.activate', {target: 'META_CONTEXT_MENU_GIVE_FEEDBACK', mode: 'immersive'})
                }}
              >
                Give feedback
                <ActionList.LeadingVisual>
                  <CommentIcon />
                </ActionList.LeadingVisual>
              </ActionList.Item>
              <ActionList.LinkItem
                href="/settings/copilot"
                onClick={() =>
                  sendEvent('dotcom_chat.activate', {target: 'META_CONTEXT_MENU_SETTINGS', mode: 'immersive'})
                }
              >
                Settings
                <ActionList.LeadingVisual>
                  <GearIcon />
                </ActionList.LeadingVisual>
              </ActionList.LinkItem>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
        <UserFeedback ref={feedbackRef} />
      </div>
    </div>
  )
}
