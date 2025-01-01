import {
  ConversationFeedbackDialog,
  type FeedbackDialogRef,
} from '@github-ui/copilot-chat/components/ConversationFeedbackDialog'
import {ModelPicker} from '@github-ui/copilot-chat/components/ModelPicker'
import {PersonalInstructionsDialog} from '@github-ui/copilot-chat/components/PersonalInstructionsDialog'
import {PromptDialog} from '@github-ui/copilot-chat/components/PromptDialog'
import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {
  COPILOT_SPACES_PATH,
  isRepository,
  threadName as getThreadName,
} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {useChatState, useChatStateLens} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {getCopilotSpacePath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {setTitle} from '@github-ui/document-metadata'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {isStaff} from '@github-ui/stats'
import {useNavigate} from '@github-ui/use-navigate'
import {
  BeakerIcon,
  CommentIcon,
  CpuIcon,
  GearIcon,
  KebabHorizontalIcon,
  NoteIcon,
  PencilIcon,
  RepoIcon,
  ShareIcon,
  SidebarExpandIcon,
  TrashIcon,
} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, Label, Stack} from '@primer/react'
import {clsx} from 'clsx'
import {useMemo, useRef, useState} from 'react'
import {flushSync} from 'react-dom/profiling'

import {useBooleanState} from '../hooks/use-boolean-state'
import {useIsSharedThread} from '../hooks/use-is-shared-thread'
import {useNavigateToNewThread} from '../hooks/use-navigate-to-new-thread'
import type {CopilotImmersivePayload} from '../routes/payloads'
import {useContentPreview} from './ContentPreview/ContentPreviewContext'
import {type ConversationActionDialogName, ConversationActionDialogs, ConversationActions} from './ConversationActions'
import styles from './Header.module.css'
import {PreviewModelCapabilityWarning} from './PreviewModelCapabilityWarning'
import {ShareConversationButton} from './ShareConversationButton'
import {ShareCopilotSpaceDialog} from './ShareCopilotSpaceDialog'
import {DeleteDialog} from './Spaces/SpaceMenu'
import {SystemPromptDialog, type SystemPromptDialogRef} from './SystemPromptDialog'

export interface HeaderProps {
  showModelPicker?: boolean
  showPreviewPaneButton?: boolean
  conversationSpecificItems?: React.ReactNode
}

export function Header({showModelPicker = true, showPreviewPaneButton = true, conversationSpecificItems}: HeaderProps) {
  const manager = useChatManager()
  const {
    currentTopic,
    repoCustomInstructionsEnabled,
    selectedThreadID,
    customCopilots,
    customCopilotId,
    messagesLoading,
  } = useChatState()
  const threadName = useChatStateLens(s => getThreadName(manager.getSelectedThread(s)))
  setTitle(`${threadName} · GitHub Copilot`)
  const feedbackRef = useRef<FeedbackDialogRef>(null)
  const systemPromptRef = useRef<SystemPromptDialogRef>(null)
  const repo = isRepository(currentTopic) ? currentTopic : undefined
  const navigateToNewThread = useNavigateToNewThread()

  const userIsStaff = useMemo(() => {
    return isStaff()
  }, [])

  const showPromptDialog = isFeatureEnabled('copilot_staff_prompt_dialog') && userIsStaff
  const showSystemPrompt = useFeatureFlag('copilot_immersive_view_system_prompt')

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

  const showRepoInstructions = canUseRepoCustomInstructions && repo?.customInstructions

  const [loading, startLoading, stopLoading] = useBooleanState(false)
  const isSharedThread = useIsSharedThread()
  const {canShareThread} = useAppPayload<CopilotImmersivePayload>()
  const messagesLoaded = messagesLoading.state === 'loaded'

  const navigate = useNavigate()
  const isSpaceForm = ssrSafeLocation?.pathname?.startsWith(COPILOT_SPACES_PATH)
  const selectedCopilotSpace = customCopilots?.find(customCopilot => customCopilot.id === customCopilotId)
  const [showDeleteSpaceDialog, setShowDeleteSpaceDialog] = useState(false)
  const [showShareSpaceDialog, setShowShareSpaceDialog] = useState(false)

  const closeShareSpaceDialog = () => {
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_SHARE_DIALOG_CLOSE', mode: 'immersive'})
    setShowShareSpaceDialog(false)
  }

  const closeDeleteSpaceDialog = () => {
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_DELETE_DIALOG_CLOSE', mode: 'immersive'})
    setShowDeleteSpaceDialog(false)
  }

  const onEditCopilotSpace = () => {
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_CONTEXT_MENU_EDIT', mode: 'immersive'})

    if (!selectedCopilotSpace) return

    manager.dispatch({type: 'SET_CUSTOM_COPILOT_ID', customCopilotId: selectedCopilotSpace.id})
    navigate(getCopilotSpacePath(selectedCopilotSpace.id))
  }

  const openShareSpaceDialog = () => {
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_CONTEXT_MENU_SHARE', mode: 'immersive'})
    setShowShareSpaceDialog(true)
  }
  const openDeleteSpaceDialog = () => {
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_CONTEXT_MENU_DELETE', mode: 'immersive'})
    setShowDeleteSpaceDialog(true)
  }

  const deleteSpace = async () => {
    if (selectedCopilotSpace) {
      navigate(COPILOT_SPACES_PATH)
      await manager.deleteCopilotSpace(selectedCopilotSpace)
    }
  }

  return (
    <div className={styles.header}>
      <div className={styles.centerControls}>
        {showModelPicker && (
          <>
            <ModelPicker onNewThreadSelected={navigateToNewThread} limited={isLicensedLimited} />
            <PreviewModelCapabilityWarning />
          </>
        )}
      </div>

      <div className={styles.rightControls}>
        {canShareThread && !isSharedThread && selectedThreadID && messagesLoaded && <ShareConversationButton />}
        <Stack direction="horizontal" gap="condensed">
          <ActionMenu>
            <ActionMenu.Anchor>
              <IconButton
                icon={KebabHorizontalIcon}
                aria-label="Menu"
                onClick={() => sendEvent('dotcom_chat.activate', {target: 'META_CONTEXT_MENU', mode: 'immersive'})}
                className={clsx(hasPromptOverride && styles.editedPromptIndicator)}
                ref={anchorRef}
                loading={loading}
              />
            </ActionMenu.Anchor>

            <ActionMenu.Overlay width="small">
              <ActionList>
                {/* Conversation-specific items (can be replaced with user-provided prop) */}
                {selectedThreadID &&
                  (conversationSpecificItems ? (
                    conversationSpecificItems
                  ) : (
                    <>
                      <ActionList.Group>
                        <ActionList.GroupHeading>Conversation</ActionList.GroupHeading>
                        <ConversationActions onOpenDialog={setConversationDialog} showShare={false} />
                      </ActionList.Group>
                      <ActionList.Divider />
                    </>
                  ))}

                {/* Space-related items */}
                {selectedCopilotSpace ? (
                  <>
                    <ActionList.Group>
                      <ActionList.GroupHeading>Space</ActionList.GroupHeading>
                      {!isSpaceForm && (
                        <ActionList.Item onSelect={onEditCopilotSpace}>
                          <ActionList.LeadingVisual>
                            <PencilIcon />
                          </ActionList.LeadingVisual>
                          Edit
                        </ActionList.Item>
                      )}
                      <ActionList.Item onSelect={openShareSpaceDialog}>
                        <ActionList.LeadingVisual>
                          <ShareIcon />
                        </ActionList.LeadingVisual>
                        Share
                      </ActionList.Item>
                      {isSpaceForm && (
                        <ActionList.Item variant="danger" onSelect={openDeleteSpaceDialog}>
                          <ActionList.LeadingVisual>
                            <TrashIcon />
                          </ActionList.LeadingVisual>
                          Delete
                        </ActionList.Item>
                      )}
                    </ActionList.Group>
                    <ActionList.Divider />
                  </>
                ) : null}

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
                  {showSystemPrompt && (
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
                  )}
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
              aria-label="Open panel"
              onClick={() => {
                sendEvent('dotcom_chat.activate', {target: 'BROWSER_OPEN_BUTTON', mode: 'immersive'})
                openPreviewPane()
              }}
            />
          )}

          <SystemPromptDialog ref={systemPromptRef} />
          <ConversationFeedbackDialog ref={feedbackRef} mode="immersive" />
          {selectedThreadID && (
            <ConversationActionDialogs
              visibleDialog={conversationDialog}
              onClose={() => {
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
        </Stack>
      </div>

      {showStaffDialog && <PromptDialog promptDialogRef={staffDialogRef} onDismiss={() => setShowStaffDialog(false)} />}
      {showPersonalInstructionsDialog && (
        <PersonalInstructionsDialog onDismiss={() => setShowPersonalInstructionsDialog(false)} />
      )}
      {showDeleteSpaceDialog && selectedCopilotSpace ? (
        <DeleteDialog onCancel={closeDeleteSpaceDialog} onConfirm={deleteSpace} />
      ) : null}
      {showShareSpaceDialog && selectedCopilotSpace ? (
        <ShareCopilotSpaceDialog closeDialog={closeShareSpaceDialog} customCopilotId={selectedCopilotSpace.id} />
      ) : null}
    </div>
  )
}
