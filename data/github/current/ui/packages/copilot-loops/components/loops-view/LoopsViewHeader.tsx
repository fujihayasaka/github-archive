import {
  ConversationFeedbackDialog,
  type FeedbackDialogRef,
} from '@github-ui/copilot-chat/components/ConversationFeedbackDialog'
import {sendEvent} from '@github-ui/hydro-analytics'
import {CommentIcon, GearIcon, KebabHorizontalIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {useRef} from 'react'
import styles from './LoopsViewHeader.module.css'

export function LoopsViewHeader() {
  const feedbackRef = useRef<FeedbackDialogRef>(null)
  const anchorRef = useRef<HTMLButtonElement>(null)

  return (
    <div className={styles.header}>
      <div className={styles.rightControls}>
        <ActionMenu anchorRef={anchorRef}>
          <ActionMenu.Anchor>
            <IconButton
              icon={KebabHorizontalIcon}
              aria-label="Menu"
              onClick={() => sendEvent('dotcom_chat.activate', {target: 'META_CONTEXT_MENU', mode: 'immersive'})}
            />
          </ActionMenu.Anchor>

          <ActionMenu.Overlay width="small">
            <ActionList>
              <ActionList.Group>
                <ActionList.Item
                  onSelect={() => {
                    feedbackRef.current?.openDialog()
                    sendEvent('dotcom_chat.activate', {
                      target: 'META_CONTEXT_MENU_GIVE_FEEDBACK',
                      mode: 'immersive',
                    })
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
                  <ActionList.LeadingVisual>
                    <GearIcon />
                  </ActionList.LeadingVisual>
                  Settings
                </ActionList.LinkItem>
              </ActionList.Group>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
        <ConversationFeedbackDialog ref={feedbackRef} mode="immersive" returnFocusRef={anchorRef} />
      </div>
    </div>
  )
}
