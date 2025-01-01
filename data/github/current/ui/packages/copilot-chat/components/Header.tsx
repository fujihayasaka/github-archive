import {isFeatureEnabled} from '@github-ui/feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'
import {IconButtonWithTooltip} from '@github-ui/icon-button-with-tooltip'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {isStaff} from '@github-ui/stats'
import {useNavigate} from '@github-ui/use-navigate'
import {
  ArrowLeftIcon,
  BeakerIcon,
  ChevronDownIcon,
  ChevronUpIcon,
  CommentDiscussionIcon,
  EyeClosedIcon,
  HistoryIcon,
  KebabHorizontalIcon,
  NoteIcon,
  PlusIcon,
  ScreenFullIcon,
  ToolsIcon,
  TrashIcon,
  XIcon,
} from '@primer/octicons-react'
import {ActionList, ActionMenu, Box, Button, Heading, Label} from '@primer/react'
import {useCallback, useMemo, useRef, useState} from 'react'

import {COPILOT_PATH, isRepository} from '../utils/copilot-chat-helpers'
import {STAFF_PROMPT_DIALOG_FF} from '../utils/copilot-chat-manager'
import {type CopilotChatThread, DialogType} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {ConversationFeedbackDialog, type FeedbackDialogRef} from './ConversationFeedbackDialog'
import {PersonalInstructionsDialog} from './PersonalInstructionsDialog'
import {ActionMenuOverlay} from './PortalContainerUtils'
import {StaffDialogs} from './StaffDialogs'

export interface HeaderProps {
  staffDialogRef: React.MutableRefObject<HTMLDivElement | null>
  showStaffDialog: DialogType
  setShowStaffDialog: (value: DialogType) => void
  isImmersive?: boolean
  isResponding?: boolean
  hasUnreadMessages?: boolean
  startResize?: (e: React.MouseEvent, horizontal: boolean, vertical: boolean) => void
}

export const Header = (props: HeaderProps) => {
  const state = useChatState()
  const manager = useChatManager()
  const [showPersonalInstructionsDialog, setShowPersonalInstructionsDialog] = useState(false)

  const navigate = useNavigate()
  const thread = manager.getSelectedThread(state)
  const {showTopicPicker, messages, currentTopic, streamingMessage} = state
  const threadName = thread?.name ?? state.restoredThreadTitle

  const immersiveURL = useMemo(() => {
    if (thread) {
      return `${COPILOT_PATH}/c/${thread.id}`
    } else if (currentTopic && isRepository(currentTopic)) {
      return `${COPILOT_PATH}/r/${currentTopic.ownerLogin}/${currentTopic.name}`
    } else {
      return COPILOT_PATH
    }
  }, [thread, currentTopic])

  const handleThreadDelete = useCallback(async () => {
    return thread && manager.deleteThread(thread)
  }, [thread, manager])

  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')
  const noFloatingButton = isFeatureEnabled('copilot_no_floating_button')

  return (
    <Box
      sx={{
        display: 'flex',
        gap: 2,
        p: 2,
        pl: state.mode === 'immersive' ? 1 : 3,
        borderBottom: showTopicPicker ? 'none' : '1px solid',
        borderColor: 'border.default',
        justifyContent: 'space-between',
        alignItems: 'center',
      }}
    >
      <Box sx={{display: 'flex', flex: 1, minWidth: 0}}>
        {state.currentView === 'thread' ? (
          !showTopicPicker &&
          !props.isImmersive &&
          messages.length === 0 &&
          state.chatIsOpen && (
            <Heading
              as="h2"
              sx={{
                fontSize: 1,
                display: 'flex',
                alignItems: 'center',
                flexGrow: 1,
                gap: 2,
                minWidth: 0,
                cursor: 'default',
              }}
            >
              {state.currentView === 'thread' ? (
                <>
                  {threadName ? (
                    <span className="Truncate">
                      {/* Primer tooltips are broken in portals, so we need to use a title here */}
                      {/* eslint-disable-next-line github/a11y-no-title-attribute */}
                      <span className="Truncate-text" title={threadName}>
                        {threadName}
                      </span>
                    </span>
                  ) : props.isResponding && !state.chatIsOpen ? (
                    <>Responding…</>
                  ) : !state.chatIsOpen ? (
                    <>Ask Copilot</>
                  ) : (
                    !showTopicPicker && <>New conversation</>
                  )}
                </>
              ) : (
                'Copilot'
              )}
            </Heading>
          )
        ) : (
          <ReturnToCurrentThreadButton />
        )}
      </Box>

      <Box
        sx={{
          display: 'flex',
          alignItems: 'center',
        }}
      >
        {state.chatIsOpen && (
          <>
            {state.renderBetaLabel &&
              (lifecycleLabelNameEnabled ? (
                <BetaLabel className="mr-2" />
              ) : (
                <Label variant="success" sx={{mr: 2}}>
                  Beta
                </Label>
              ))}
            {state.currentView === 'thread' ? (
              <>
                <IconButtonWithTooltip
                  hidden={messages.length === 0}
                  variant="invisible"
                  icon={PlusIcon}
                  label="New conversation"
                  tooltipDirection="s"
                  onClick={async () => {
                    await manager.selectThread(null)
                  }}
                  sx={{color: 'fg.muted'}}
                />
                <ThreadOptionButton
                  handleDelete={handleThreadDelete}
                  thread={thread}
                  setShowStaffDialog={props.setShowStaffDialog}
                  setShowPersonalInstructionsDialog={setShowPersonalInstructionsDialog}
                />
              </>
            ) : (
              <IconButtonWithTooltip
                variant="invisible"
                icon={PlusIcon}
                label="New conversation"
                tooltipDirection="w"
                onClick={async () => {
                  await manager.selectThread(null)
                }}
                sx={{color: 'fg.muted'}}
              />
            )}
          </>
        )}

        {!props.isImmersive && (
          <>
            {state.chatIsOpen && (
              <Box
                sx={{
                  mx: 2,
                  height: '20px',
                  width: '1px',
                  bg: 'border.muted',
                }}
              />
            )}
            <IconButtonWithTooltip
              variant="invisible"
              icon={ScreenFullIcon}
              label="Take conversation to immersive"
              tooltipDirection={state.chatIsOpen ? 'sw' : 'w'}
              onClick={() => {
                navigate(immersiveURL)
                sendEvent('dotcom_chat.activate', {target: 'IMMERSIVE_OPTION', mode: 'assistive'})
              }}
              disabled={!!streamingMessage}
              sx={{color: 'fg.muted'}}
            />
            {noFloatingButton ? (
              <IconButtonWithTooltip
                variant="invisible"
                icon={XIcon}
                label="Close chat"
                tooltipDirection="sw"
                onClick={() => manager.closeChat()}
                sx={{color: 'fg.muted'}}
                data-hotkey="Shift+Z"
              />
            ) : (
              <IconButtonWithTooltip
                variant="invisible"
                icon={state.chatIsOpen ? ChevronDownIcon : ChevronUpIcon}
                label={state.chatIsOpen ? 'Collapse' : 'Expand'}
                tooltipDirection={state.chatIsOpen ? 'sw' : 'w'}
                onClick={
                  state.chatIsOpen
                    ? () => manager.closeChat()
                    : () => manager.openChat(thread, state.currentView, 'header', state.chatVisibleSettingPath)
                }
                sx={{color: 'fg.muted'}}
                data-hotkey="Shift+Z"
              />
            )}
          </>
        )}
      </Box>
      <StaffDialogs
        dialogType={props.showStaffDialog}
        staffDialogRef={props.staffDialogRef}
        onDismiss={() => props.setShowStaffDialog(DialogType.None)}
      />
      {showPersonalInstructionsDialog && (
        <PersonalInstructionsDialog onDismiss={() => setShowPersonalInstructionsDialog(false)} />
      )}
    </Box>
  )
}

const ReturnToCurrentThreadButton = () => {
  const {mode} = useChatState()
  const manager = useChatManager()

  return (
    <Button
      leadingVisual={ArrowLeftIcon}
      variant="invisible"
      onClick={() => manager.viewCurrentThread()}
      sx={{color: 'fg.muted', marginLeft: mode === 'assistive' ? '-8px' : undefined}}
    >
      Back
    </Button>
  )
}

interface ThreadOptionButtonProps {
  handleDelete: () => void
  thread?: CopilotChatThread | null
  setShowStaffDialog: (value: DialogType) => void
  setShowPersonalInstructionsDialog: (value: boolean) => void
}

export const ThreadOptionButton = (props: ThreadOptionButtonProps) => {
  const [open, setOpen] = useState(false)
  const {chatVisibleSettingPath, currentTopic, mode, repoCustomInstructionsEnabled} = useChatState()

  const manager = useChatManager()
  const feedbackRef = useRef<FeedbackDialogRef>(null)
  const noFloatingButton = isFeatureEnabled('copilot_no_floating_button')
  const showPromptDialog = isFeatureEnabled(STAFF_PROMPT_DIALOG_FF)
  const repo = isRepository(currentTopic) ? currentTopic : undefined
  const canUseRepoCustomInstructions =
    copilotFeatureFlags.repoCustomInstructions || copilotFeatureFlags.repoCustomInstructionsPreview

  const handleClickViewAll = useCallback(() => {
    // We might not have tried to load any threads but the latest one yet.
    void manager.fetchThreads()

    manager.viewAllThreads()
    sendEvent('copilot.view-conversations-clicked')
  }, [manager])

  const handleSelectDelete = () => {
    props.handleDelete()
    setOpen(false)
  }

  const userIsStaff = useMemo(() => {
    return isStaff()
  }, [])

  const deleteDisabled = !props.thread

  return (
    <>
      <ActionMenu open={open} onOpenChange={() => setOpen(prev => !prev)}>
        <ActionMenu.Anchor>
          <IconButtonWithTooltip
            icon={KebabHorizontalIcon}
            variant="invisible"
            label="Conversation options"
            tooltipDirection="s"
            hideTooltip={open}
            sx={{color: 'fg.muted'}}
          />
        </ActionMenu.Anchor>
        <ActionMenuOverlay>
          <ActionList>
            {canUseRepoCustomInstructions && repo?.customInstructions && (
              <ActionList.Item
                onSelect={() => {
                  manager.toggleRepoCustomInstructions(!repoCustomInstructionsEnabled)
                }}
              >
                <ActionList.LeadingVisual>
                  <NoteIcon />
                </ActionList.LeadingVisual>
                {repoCustomInstructionsEnabled ? 'Disable custom instructions' : 'Enable custom instructions'}
              </ActionList.Item>
            )}
            <ActionList.Item
              variant={deleteDisabled ? 'default' : 'danger'}
              onSelect={handleSelectDelete}
              disabled={deleteDisabled}
              aria-describedby="delete-conversation-description"
            >
              <ActionList.LeadingVisual>
                <TrashIcon />
              </ActionList.LeadingVisual>
              Delete conversation
              <p id="delete-conversation-description" className="sr-only">
                This is a destructive action that cannot be undone
              </p>
            </ActionList.Item>
            <ActionList.Divider />
            <ActionList.Item onSelect={() => props.setShowPersonalInstructionsDialog(true)}>
              <ActionList.LeadingVisual>
                <ToolsIcon />
              </ActionList.LeadingVisual>
              Personal instructions
            </ActionList.Item>
            {mode === 'assistive' && (
              <ActionList.Item onSelect={handleClickViewAll}>
                <ActionList.LeadingVisual>
                  <HistoryIcon />
                </ActionList.LeadingVisual>
                View all conversations
              </ActionList.Item>
            )}
            <ActionList.Item
              onSelect={() => {
                feedbackRef.current?.openDialog()
                sendEvent('dotcom_chat.activate', {target: 'META_CONTEXT_MENU_GIVE_FEEDBACK', mode: 'assistive'})
              }}
            >
              <ActionList.LeadingVisual>
                <CommentDiscussionIcon />
              </ActionList.LeadingVisual>
              Give feedback
            </ActionList.Item>
            {mode === 'assistive' && !noFloatingButton && (
              <ActionList.Item
                onSelect={() => {
                  manager.hideChat(chatVisibleSettingPath)
                }}
              >
                <ActionList.LeadingVisual>
                  <EyeClosedIcon />
                </ActionList.LeadingVisual>
                Hide Copilot chat
              </ActionList.Item>
            )}
            {userIsStaff && (
              <ActionList.Item onSelect={() => props.setShowStaffDialog(DialogType.Experiments)}>
                <ActionList.LeadingVisual>
                  <BeakerIcon />
                </ActionList.LeadingVisual>
                Configure experiments
                <ActionList.TrailingVisual>
                  <Label variant="attention">Staff</Label>
                </ActionList.TrailingVisual>
              </ActionList.Item>
            )}
            {userIsStaff && showPromptDialog && (
              <ActionList.Item onSelect={() => props.setShowStaffDialog(DialogType.Prompt)}>
                <ActionList.LeadingVisual>
                  <BeakerIcon />
                </ActionList.LeadingVisual>
                Adjust prompts
                <ActionList.TrailingVisual>
                  <Label variant="attention">Staff</Label>
                </ActionList.TrailingVisual>
              </ActionList.Item>
            )}
          </ActionList>
        </ActionMenuOverlay>
      </ActionMenu>
      <ConversationFeedbackDialog ref={feedbackRef} mode="assistive" />
    </>
  )
}
