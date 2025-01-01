import {
  ConversationFeedbackDialog,
  type FeedbackDialogRef,
} from '@github-ui/copilot-chat/components/ConversationFeedbackDialog'
import {PersonalInstructionsDialog} from '@github-ui/copilot-chat/components/PersonalInstructionsDialog'
import {PromptDialog} from '@github-ui/copilot-chat/components/PromptDialog'
import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {useSelectedCustomCopilotId} from '@github-ui/copilot-chat/hooks/use-selected-custom-copilot-id'
import {
  getCustomInstructionsFromReferences,
  threadName as getThreadName,
} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {useChatState, useChatStateLens} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {findCustomCopilot} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {getSelectedThread} from '@github-ui/copilot-chat/utils/get-selected-thread'
import {setTitle} from '@github-ui/document-metadata'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {isStaff} from '@github-ui/stats'
import {
  BeakerIcon,
  CommentIcon,
  CopilotIcon,
  CpuIcon,
  GearIcon,
  KebabHorizontalIcon,
  ListUnorderedIcon,
  NoteIcon,
  RepoIcon,
  SidebarExpandIcon,
} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, Label} from '@primer/react'
import {clsx} from 'clsx'
import {useEffect, useMemo, useRef, useState} from 'react'
import {flushSync} from 'react-dom'

import {useBooleanState} from '../hooks/use-boolean-state'
import {useIsSharedThread} from '../hooks/use-is-shared-thread'
import type {CopilotImmersivePayload} from '../routes/payloads'
import {useContentPreview} from './ContentPreview/ContentPreviewContext'
import {type ConversationActionDialogName, ConversationActionDialogs, ConversationActions} from './ConversationActions'
import {ConversationSharingButton} from './ConversationSharingButton'
import styles from './Header.module.css'
import {ManageSharedConversationsDialog} from './ManageSharedConversationsDialog'
import {useGlobalNavigation} from './Spaces/hooks/use-global-navigation'
import {SystemPromptDialog, type SystemPromptDialogRef} from './SystemPromptDialog'

export interface HeaderProps {
  showModelPicker?: boolean
  showPreviewPaneButton?: boolean
  conversationSpecificItems?: React.ReactNode
  isSidebarOpen?: boolean
  customButtons?: React.ReactNode
}

export function Header({showPreviewPaneButton = true, conversationSpecificItems, customButtons}: HeaderProps) {
  const manager = useChatManager()
  const state = useChatState()
  const {currentTopic, repoCustomInstructionsEnabled, selectedThreadID, threads, messagesLoading, currentReferences} =
    state
  const threadName = useChatStateLens(s => getThreadName(getSelectedThread(s)))
  const isSharedThread = useIsSharedThread()
  const selectedCopilotSpaceId = useSelectedCustomCopilotId()
  const selectedCopilotSpace = findCustomCopilot(state.customCopilots, selectedCopilotSpaceId)

  if (selectedCopilotSpace) {
    setTitle(`${threadName} · GitHub Copilot Spaces · ${selectedCopilotSpace.name}`)
  } else if (isSharedThread) {
    setTitle(`Shared conversation · GitHub Copilot`)
  } else {
    setTitle(`${threadName} · GitHub Copilot`)
  }

  const {updateGlobalNavigationBreadcrumbs} = useGlobalNavigation()

  useEffect(() => {
    updateGlobalNavigationBreadcrumbs()
  }, [updateGlobalNavigationBreadcrumbs, selectedCopilotSpaceId])

  const feedbackRef = useRef<FeedbackDialogRef>(null)
  const systemPromptRef = useRef<SystemPromptDialogRef>(null)

  const userIsStaff = useMemo(() => {
    return isStaff()
  }, [])

  const showPromptDialog = isFeatureEnabled('copilot_staff_prompt_dialog') && userIsStaff

  const [showStaffDialog, setShowStaffDialog] = useState(false)
  const [showPersonalInstructionsDialog, setShowPersonalInstructionsDialog] = useState(false)
  const staffDialogRef = useRef<HTMLDivElement>(null)

  const hasPromptOverride = !!copilotLocalStorage.settings?.instructionPrompt
  const {isLicensedLimited} = useEntitlement()

  const canUseRepoCustomInstructions =
    copilotFeatureFlags.repoCustomInstructions || copilotFeatureFlags.repoCustomInstructionsPreview

  const {previewPaneOpen, openPreviewPane} = useContentPreview()

  const anchorRef = useRef<HTMLButtonElement>(null)

  const [conversationDialog, setConversationDialog] = useState<ConversationActionDialogName | null>(null)

  let customInstructions = currentTopic?.customInstructions || []
  if (copilotFeatureFlags.topicsAsReferences) {
    customInstructions = getCustomInstructionsFromReferences(currentReferences)
  }

  const showRepoInstructions = canUseRepoCustomInstructions && customInstructions.length > 0

  const [loading, startLoading, stopLoading] = useBooleanState(false)
  const {canShareThread} = useAppPayload<CopilotImmersivePayload>()
  const messagesLoaded = messagesLoading.state === 'loaded'

  const [showManageSharedDialog, setShowManageSharedDialog] = useState(false)
  const showShareButton =
    canShareThread && !isSharedThread && selectedThreadID && !selectedCopilotSpaceId && messagesLoaded

  return (
    <div className={styles.header}>
      <div className={styles.rightControls}>
        {showShareButton && <ConversationSharingButton />}
        {customButtons}
        <ActionMenu anchorRef={anchorRef}>
          <ActionMenu.Anchor>
            <IconButton
              icon={KebabHorizontalIcon}
              aria-label="Menu"
              onClick={() => sendEvent('dotcom_chat.activate', {target: 'META_CONTEXT_MENU', mode: 'immersive'})}
              className={clsx(hasPromptOverride && styles.editedPromptIndicator)}
              loading={loading}
            />
          </ActionMenu.Anchor>

          <ActionMenu.Overlay width="small">
            <ActionList>
              {/* Integration specific items */}
              {conversationSpecificItems}

              {/* Conversation-specific items (can be replaced with user-provided prop) */}
              {selectedThreadID && !isSharedThread && (
                <>
                  <ActionList.Group>
                    <ActionList.GroupHeading>Conversation</ActionList.GroupHeading>
                    <ConversationActions
                      onOpenDialog={setConversationDialog}
                      isShared={Boolean(threads.get(selectedThreadID)?.sharedID)}
                      showShare={!selectedCopilotSpaceId}
                      hideShareOnDesktop
                    />
                  </ActionList.Group>
                  <ActionList.Divider />
                </>
              )}

              {/* Prompt-related items */}
              <ActionList.Group>
                <ActionList.GroupHeading>Prompt</ActionList.GroupHeading>
                {showRepoInstructions && (
                  <ActionList.Item
                    onSelect={() => {
                      manager.toggleRepoCustomInstructions(!repoCustomInstructionsEnabled)
                    }}
                  >
                    <ActionList.LeadingVisual>
                      <RepoIcon />
                    </ActionList.LeadingVisual>
                    {repoCustomInstructionsEnabled ? 'Disable custom instructions' : 'Enable custom instructions'}
                  </ActionList.Item>
                )}
                <ActionList.Item
                  onSelect={() => {
                    setShowPersonalInstructionsDialog(true)
                    sendEvent('dotcom_chat.activate', {
                      target: 'META_CONTEXT_MENU_PERSONAL_INSTRUCTIONS',
                      mode: 'immersive',
                    })
                  }}
                >
                  <ActionList.LeadingVisual>
                    <NoteIcon />
                  </ActionList.LeadingVisual>
                  Personal instructions
                </ActionList.Item>
                <ActionList.Item
                  onSelect={() => {
                    systemPromptRef.current?.openDialog()
                    sendEvent('dotcom_chat.activate', {
                      target: 'META_CONTEXT_MENU_SYSTEM_PROMPT',
                      mode: 'immersive',
                    })
                  }}
                >
                  <ActionList.LeadingVisual>
                    <CpuIcon />
                  </ActionList.LeadingVisual>
                  System prompt
                </ActionList.Item>
                {showPromptDialog && (
                  <ActionList.Item onSelect={() => setShowStaffDialog(true)}>
                    <ActionList.LeadingVisual>
                      {hasPromptOverride ? (
                        <span className={clsx(styles.editedPromptIndicator, styles.leadingVisual)}>
                          <BeakerIcon />
                        </span>
                      ) : (
                        <BeakerIcon />
                      )}
                    </ActionList.LeadingVisual>
                    Edit prompt
                    <ActionList.TrailingVisual>
                      <Label variant="attention">Staff</Label>
                    </ActionList.TrailingVisual>
                  </ActionList.Item>
                )}
              </ActionList.Group>
              <ActionList.Divider />

              <ActionList.Group>
                <ActionList.Item
                  onSelect={() => {
                    setShowManageSharedDialog(true)
                  }}
                >
                  Manage shared conversations
                  <ActionList.LeadingVisual>
                    <ListUnorderedIcon />
                  </ActionList.LeadingVisual>
                </ActionList.Item>
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
                {isLicensedLimited && (
                  <>
                    <ActionList.LinkItem
                      href="/github-copilot/signup/copilot_individual"
                      onClick={() =>
                        sendEvent('dotcom_chat.activate', {
                          target: 'META_CONTEXT_MENU_UPGRADE_PRO',
                          mode: 'immersive',
                        })
                      }
                    >
                      Upgrade to Pro
                      <ActionList.LeadingVisual>
                        <CopilotIcon />
                      </ActionList.LeadingVisual>
                    </ActionList.LinkItem>
                  </>
                )}
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
              </ActionList.Group>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>

        {/* Preview Pane button (conditionally displayed) */}
        {showPreviewPaneButton && !previewPaneOpen && (
          <IconButton
            icon={SidebarExpandIcon}
            aria-label="Open workbench"
            onClick={() => {
              sendEvent('dotcom_chat.activate', {target: 'BROWSER_OPEN_BUTTON', mode: 'immersive'})
              openPreviewPane()
            }}
          />
        )}

        <SystemPromptDialog ref={systemPromptRef} />
        <ConversationFeedbackDialog ref={feedbackRef} mode="immersive" returnFocusRef={anchorRef} />
        {selectedThreadID && (
          <ConversationActionDialogs
            visibleDialog={conversationDialog}
            onClose={() => {
              // eslint-disable-next-line @eslint-react/dom/no-flush-sync
              flushSync(() => setConversationDialog(null))
              anchorRef.current?.focus()
            }}
            threadName={threadName}
            threadId={selectedThreadID}
            selectedThreadId={selectedThreadID}
            onStartLoading={startLoading}
            onFinishLoading={stopLoading}
          />
        )}
      </div>

      {showStaffDialog && <PromptDialog promptDialogRef={staffDialogRef} onDismiss={() => setShowStaffDialog(false)} />}
      {showPersonalInstructionsDialog && (
        <PersonalInstructionsDialog
          onDismiss={() => setShowPersonalInstructionsDialog(false)}
          returnFocusRef={anchorRef}
        />
      )}
      {showManageSharedDialog && (
        <ManageSharedConversationsDialog
          closeDialog={() => {
            setShowManageSharedDialog(false)
          }}
        />
      )}
    </div>
  )
}
