import {CopilotReferencePreviewDialog} from '@github-ui/copilot-reference-preview/CopilotReferencePreviewDialog'
import type {PathFunction} from '@github-ui/paths'
import {type ReactPartialAnchorProps, useOnAnchorClick} from '@github-ui/react-core/react-partial-anchor'
import {ScreenSize, ScreenSizeProvider, useScreenSize} from '@github-ui/screen-size'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {CopilotIcon} from '@primer/octicons-react'
import {Box, Button, IconButton, Popover} from '@primer/react'
import {Tooltip} from '@primer/react/deprecated'
import React, {useCallback, useEffect, useRef, useState} from 'react'

import {Chat} from './components/Chat'
import {ChatPanel} from './components/ChatPanel'
import {Header} from './components/Header'
import {ChatPortalContainer} from './components/PortalContainerUtils'
import {ThreadListView} from './components/ThreadListView'
import {copilotChatHeaderButtonID} from './utils/constants'
import type {AddCopilotChatReferenceEvent, SearchCopilotEvent, SymbolChangedEvent} from './utils/copilot-chat-events'
import {
  subscribeAddCopilotChatReference,
  subscribeOpenCopilotChat,
  subscribeSearchCopilot,
  subscribeSymbolChanged,
} from './utils/copilot-chat-events'
import {isRepository, makeRepositoryReference} from './utils/copilot-chat-helpers'
import {useResizablePanel} from './utils/copilot-chat-hooks'
import type {LoadingStateState} from './utils/copilot-chat-reducer'
import {
  type CopilotChatOrg,
  type CopilotChatPayload,
  type CopilotChatRepo,
  DialogType,
} from './utils/copilot-chat-types'
import {copilotFeatureFlags} from './utils/copilot-feature-flags'
import {copilotLocalStorage} from './utils/copilot-local-storage'
import {CopilotChatProvider, useChatState} from './utils/CopilotChatContext'
import {useChatManager} from './utils/CopilotChatManagerContext'

export interface CopilotChatProps extends CopilotChatPayload, ReactPartialAnchorProps {
  currentTopic?: CopilotChatRepo
  findFileWorkerPath: string
  ssoOrganizations: CopilotChatOrg[]
  renderPopover?: boolean
  chatIsVisible?: boolean
  chatVisibleSettingPath?: string
  renderBetaLabel?: boolean
  reviewLab: boolean
  realIp: string
  hasCEorCBAccess: boolean
}

export function CopilotChat(props: CopilotChatProps) {
  const copilotButtonRef = useRef<HTMLButtonElement>(null)
  const inputRef = useRef<HTMLTextAreaElement>(null)
  const selectedThreadID = copilotLocalStorage.selectedThreadID
  const currentReferences = copilotLocalStorage.getCurrentReferences(selectedThreadID) || []

  return (
    <ScreenSizeProvider>
      <CopilotChatProvider
        topic={props.currentTopic}
        login={props.currentUserLogin}
        apiURL={props.apiURL}
        workerPath={props.findFileWorkerPath}
        threadId={selectedThreadID}
        refs={currentReferences}
        mode="assistive"
        ssoOrganizations={props.ssoOrganizations}
        renderKnowledgeBases={props.renderKnowledgeBases}
        renderAttachKnowledgeBaseHerePopover={props.renderAttachKnowledgeBaseHerePopover}
        renderKnowledgeBaseAttachedToChatPopover={props.renderKnowledgeBaseAttachedToChatPopover}
        chatIsOpen={false}
        chatIsVisible={props.chatIsVisible}
        customInstructions={props.customInstructions}
        chatVisibleSettingPath={props.chatVisibleSettingPath}
        renderBetaLabel={props.renderBetaLabel}
        agentsPath={props.agentsPath}
        optedInToUserFeedback={props.optedInToUserFeedback}
        reviewLab={props.reviewLab}
        scrollToTop={props.scrollToTop}
        realIp={props.realIp}
        hasCEorCBAccess={props.hasCEorCBAccess}
      >
        <CopilotHeaderButton
          renderPopover={props.renderPopover || false}
          ref={copilotButtonRef}
          reactPartialAnchor={props.reactPartialAnchor}
          inputRef={inputRef}
        />
        <ChatPortalContainer />
        <ChatPanelWithHeader ref={copilotButtonRef} inputRef={inputRef} />
      </CopilotChatProvider>
    </ScreenSizeProvider>
  )
}

export const dismissNoticePath: PathFunction<{notice: string}> = ({notice}) => `/settings/dismiss-notice/${notice}`

type CopilotHeaderButtonProps = {
  renderPopover: boolean
  inputRef: React.RefObject<HTMLTextAreaElement>
} & ReactPartialAnchorProps
const CopilotHeaderButton = React.forwardRef<HTMLButtonElement, CopilotHeaderButtonProps>((props, ref) => {
  const manager = useChatManager()
  const state = useChatState()
  const selectedThread = manager.getSelectedThread(state)
  const {currentTopic, currentView} = state
  const {screenSize} = useScreenSize()

  useEffect(() => {
    return subscribeOpenCopilotChat(e => void manager.handleOpenPanelEvent(selectedThread, e, currentTopic))
  }, [currentTopic, selectedThread, manager])

  useEffect(() => {
    return subscribeAddCopilotChatReference((e: AddCopilotChatReferenceEvent) => {
      void manager.handleAddReferenceEvent(e)
    })
  }, [selectedThread, manager, state.currentReferences])

  useEffect(() => {
    return subscribeSymbolChanged((e: SymbolChangedEvent) => {
      if (copilotFeatureFlags.implicitContext) {
        void manager.handleSymbolChangedEvent(e)
      }
    })
  })

  useEffect(() => {
    return subscribeSearchCopilot((e: SearchCopilotEvent) => {
      void manager.handleSearchCopilotEvent(e)
    })
  }, [manager])

  useEffect(() => {
    const url = new URL(window.location.href, window.location.origin)
    const params = url.searchParams
    const threadId = state.selectedThreadID
    // copilot=1 url param means that we have opened the page with the intetion to open the chat
    // with the threadId that was set in the immersive view
    if (params.get('copilot') === '1' && threadId) {
      const thread = state.threads.get(threadId) ?? null
      void manager.openChat(thread, currentView, 'immersive', state.chatVisibleSettingPath)
      url.searchParams.delete('copilot')
      window.history.pushState(null, '', url.toString())
    }
  }, [manager, state.selectedThreadID, state.threads, currentView, state.chatVisibleSettingPath])

  useEffect(() => {
    if (state.chatIsVisible && !copilotLocalStorage.getCollapsedState() && screenSize > ScreenSize.large) {
      void manager.openChat(selectedThread, state.currentView, 'page load', state.chatVisibleSettingPath)
    }

    // evaluate once when the component is mounted to see if the chat should be opened.
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const openChat = useCallback(() => {
    if (!state.chatIsOpen) {
      void manager.openChat(
        selectedThread,
        currentView,
        'header',
        state.chatVisibleSettingPath,
        isRepository(currentTopic) ? makeRepositoryReference(currentTopic) : undefined,
      )
    } else if (props.inputRef.current) {
      props.inputRef.current.focus()
    }
  }, [
    currentTopic,
    currentView,
    manager,
    props.inputRef,
    selectedThread,
    state.chatIsOpen,
    state.chatVisibleSettingPath,
  ])

  if (props.reactPartialAnchor) {
    return (
      <Box sx={{position: 'relative'}}>
        <ExternalAnchorListener reactPartialAnchor={props.reactPartialAnchor} onClick={openChat} />
        {props.renderPopover ? <WelcomePopover renderPopover /> : <></>}
      </Box>
    )
  }

  return (
    <Box sx={{position: 'relative'}} className="AppHeader-CopilotChatButton">
      <Tooltip aria-label="Chat with Copilot" direction="s">
        <div>
          {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
          <IconButton
            unsafeDisableTooltip
            ref={ref}
            id={copilotChatHeaderButtonID}
            icon={CopilotIcon}
            aria-label="Chat with Copilot"
            aria-controls="copilot-chat-panel"
            onClick={openChat}
            className="AppHeader-button"
            sx={{
              backgroundColor: 'transparent',
              borderColor: 'border.default',
              color: 'fg.muted',
              mb: 1,
              '&:hover': {
                backgroundColor:
                  'var(--control-transparent-bgColor-hover, var(--color-action-list-item-default-hover-bg))',
              },
            }}
            data-testid="copilot-chat-button"
            data-hotkey="Shift+C"
            aria-expanded={false}
          />
        </div>
      </Tooltip>
      <WelcomePopover renderPopover={props.renderPopover} />
    </Box>
  )
})

function ExternalAnchorListener({reactPartialAnchor, onClick}: {onClick: () => void} & ReactPartialAnchorProps) {
  useOnAnchorClick(reactPartialAnchor!, onClick)
  return <></>
}

function WelcomePopover({renderPopover}: {renderPopover: boolean}) {
  const [showPopover, setShowPopover] = useState(renderPopover)

  const handleClosePopover = useCallback(async () => {
    setShowPopover(false)
    await verifiedFetch(dismissNoticePath({notice: 'copilot_chat_new_user_popover'}), {method: 'POST'})
  }, [setShowPopover])

  return (
    <Popover
      open={showPopover}
      caret="top-right"
      sx={{
        right: '-4px',
      }}
    >
      <Popover.Content
        sx={{
          marginTop: 2,
        }}
        data-testid="copilot-chat-cta-popover"
      >
        <p>
          You now have access to{' '}
          <a
            href="https://docs.github.com/enterprise-cloud@latest/copilot/github-copilot-enterprise/overview/about-github-copilot-enterprise"
            target="_blank"
            rel="noopener noreferrer"
          >
            Copilot Enterprise
          </a>
          {'. '}
          Use the Copilot icon to get started.
        </p>
        <Button data-testid="dismiss-copilot-chat-cta-popover" onClick={handleClosePopover}>
          Got it!
        </Button>
      </Popover.Content>
    </Popover>
  )
}

CopilotHeaderButton.displayName = 'CopilotHeaderButton'

interface ChatPanelWithHeaderProps {
  inputRef: React.RefObject<HTMLTextAreaElement>
}

const ChatPanelWithHeader = React.forwardRef<HTMLButtonElement, ChatPanelWithHeaderProps>(({inputRef}, ref) => {
  const state = useChatState()
  const manager = useChatManager()
  const staffDialogRef = useRef<HTMLDivElement>(null)
  const [showStaffDialog, setShowStaffDialog] = useState(DialogType.None)
  const [hasUnreadMessages, setHasUnreadMessages] = useState(false)
  const prevMessageCount = useRef<number>(state.messages.length)
  const prevMessageLoadingState = useRef<LoadingStateState>(state.messagesLoading.state)
  const {panelWidth, panelHeight, startResize, onResizerKeyDown} = useResizablePanel()

  useEffect(() => {
    if (
      state.messages.length > prevMessageCount.current &&
      !state.chatIsOpen &&
      prevMessageLoadingState.current === 'loaded'
    ) {
      setHasUnreadMessages(true)
    }
    prevMessageCount.current = state.messages.length
    prevMessageLoadingState.current = state.messagesLoading.state
  }, [state.chatIsOpen, state.messages.length, state.messagesLoading.state])

  useEffect(() => {
    if (state.chatIsOpen && hasUnreadMessages) {
      setHasUnreadMessages(false)
    }
  }, [hasUnreadMessages, state.chatIsOpen])

  return (
    <ChatPanel
      staffDialogRef={staffDialogRef}
      entrypointRef={ref as React.RefObject<HTMLButtonElement>}
      handleClose={(usedEscapeKey?: boolean) => {
        setShowStaffDialog(DialogType.None)
        manager.closeChat()
        const entryId = state.entryPointId ?? copilotChatHeaderButtonID

        if (usedEscapeKey && entryId) {
          const entryElement = document.getElementById(entryId)
          const scrollX = window.scrollX
          const scrollY = window.scrollY

          // Persist current scroll position by delaying focus
          setTimeout(() => {
            entryElement?.focus()
            window.scrollTo(scrollX, scrollY)
          }, 0)
        }
      }}
      showStaffDialog={showStaffDialog}
      panelWidth={panelWidth}
      panelHeight={panelHeight}
      startResize={startResize}
      onResizerKeyDown={onResizerKeyDown}
    >
      <Header
        staffDialogRef={staffDialogRef}
        showStaffDialog={showStaffDialog}
        setShowStaffDialog={setShowStaffDialog}
        isResponding={state.messages.length <= 1 && (!!state.streamingMessage || state.isWaitingOnCopilot)}
        hasUnreadMessages={hasUnreadMessages}
        startResize={startResize}
      />
      {state.chatIsOpen && (
        <Box sx={{display: 'flex', flexGrow: 1, overflowY: 'auto'}}>
          <Box sx={{display: 'flex', flexDirection: 'column', flexGrow: 1, maxWidth: '100%'}}>
            {state.currentView === 'thread' ? (
              <>
                <Chat key={state.selectedThreadID} inputRef={inputRef} panelWidth={panelWidth} />
                <CopilotReferencePreviewDialog />
              </>
            ) : (
              <ThreadListView />
            )}
          </Box>
        </Box>
      )}
    </ChatPanel>
  )
})

ChatPanelWithHeader.displayName = 'ChatPanelWithHeader'
