import {isFeatureEnabled} from '@github-ui/feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'
import {GlobalCommands, ScopedCommands} from '@github-ui/ui-commands'
import {useNavigate} from '@github-ui/use-navigate'
import {Box, Overlay} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {useCallback, useEffect, useRef} from 'react'

import {copilotChatHeaderButtonID, copilotChatPanelID, copilotChatPanelInnerID} from '../utils/constants'
import {COPILOT_PATH, isRepository} from '../utils/copilot-chat-helpers'
import {MIN_PANEL_HEIGHT, MIN_PANEL_WIDTH} from '../utils/copilot-chat-hooks'
import type {DialogType} from '../utils/copilot-chat-types'
import {copilotLocalStorage} from '../utils/copilot-local-storage'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {getSelectedThread} from '../utils/get-selected-thread'
import styles from './ChatPanel.module.css'
import FloatingButton from './FloatingButton'
import {COPILOT_CHAT_PORTAL_ROOT} from './PortalContainerUtils'

interface ChatPanelProps {
  handleClose: (usedEscapeKey?: boolean) => void
  staffDialogRef: React.MutableRefObject<HTMLDivElement | null>
  children: React.ReactNode
  showStaffDialog: DialogType
  panelWidth: number
  panelHeight: number
  startResize: (e: React.MouseEvent, horizontal: boolean, vertical: boolean) => void
  onResizerKeyDown: (e: React.KeyboardEvent) => void
  initialFocusRef: React.RefObject<HTMLTextAreaElement>
}

export const ChatPanel = (props: ChatPanelProps) => {
  const {
    children,
    initialFocusRef,
    staffDialogRef,
    handleClose,
    panelWidth,
    panelHeight,
    startResize,
    onResizerKeyDown,
  } = props
  const state = useChatState()
  const {chatIsOpen, chatIsVisible, currentTopic} = state
  const entryPointId = state.entryPointId ?? copilotChatHeaderButtonID
  const overlayRef = useRef<HTMLDivElement>(null)
  const entryPointRef = useRef<HTMLElement | null>(null)

  useEffect(() => {
    const entryElement = document.getElementById(entryPointId)
    entryPointRef.current = entryElement
  }, [entryPointId])

  const onEscape = useCallback(() => {
    if (overlayRef.current && overlayRef.current.contains(document.activeElement)) {
      handleClose(true)
    }
  }, [handleClose])

  const manager = useChatManager()
  const thread = getSelectedThread(state)
  const navigate = useNavigate()
  const navigateToImmersive = () => {
    sendEvent('dotcom_chat.activate', {target: 'IMMERSIVE_OPTION', mode: 'assistive'})

    // References are saved automatically whenever they change, but it's possible that another tab might have overwritten
    // the state since this tab was opened. Since the user is clicking in this tab, they expect these to be the references
    // that carry over into immersive.
    copilotLocalStorage.setCurrentReferences(thread?.id ?? null, state.currentReferences)

    if (thread) {
      navigate(`${COPILOT_PATH}/c/${thread.id}`)
    } else if (currentTopic && isRepository(currentTopic)) {
      navigate(`${COPILOT_PATH}/r/${currentTopic.ownerLogin}/${currentTopic.name}`)
    } else {
      navigate(COPILOT_PATH)
    }
  }

  return (
    <>
      {chatIsOpen ? (
        <Overlay
          id={copilotChatPanelID}
          className={clsx(styles.copilotChatPanel)}
          ref={overlayRef}
          portalContainerName={COPILOT_CHAT_PORTAL_ROOT}
          onEscape={onEscape}
          onClickOutside={() => {}}
          ignoreClickRefs={[staffDialogRef as React.RefObject<HTMLDivElement>]}
          initialFocusRef={initialFocusRef}
          returnFocusRef={entryPointRef}
          sx={{
            maxWidth: 'calc(100vw - 2rem)',
            height: chatIsOpen ? `${panelHeight}px` : '48px',
            // The magic 60px here corresponds to $sticky-header-height which appears on pages like issues
            // and PRs upon scrolling and can hide the chat panel header (including collapse and close buttons).
            // If the header height changes, this needs to be updated. If PRs ships in React, the bug may resolve
            // itself and we can remove the 60px.
            maxHeight: 'calc(100vh - 1rem - 60px)',
            minHeight: chatIsOpen ? `${MIN_PANEL_HEIGHT}px` : undefined,
            width: chatIsOpen ? `${panelWidth}px` : '400px',
            minWidth: `${MIN_PANEL_WIDTH}px`,
          }}
          right={8}
          bottom={8}
          anchorSide="inside-top"
          position="fixed"
          role="dialog"
          aria-labelledby={copilotChatPanelInnerID}
        >
          <GlobalCommands
            commands={{
              // This should be runnable from anywhere on the page so you can close the chat without tabbing to it
              'copilot-chat:close-assistive': () => manager.closeChat(),
            }}
          />
          <ScopedCommands
            commands={{
              // This command needs to be scoped to just the chat or it will override the browser shortcut for opening the dev console
              'copilot-chat:continue-in-immersive': navigateToImmersive,
            }}
          >
            <section id={copilotChatPanelInnerID} aria-label="Copilot chat panel" style={{height: '100%'}}>
              <Box
                sx={{
                  display: 'flex',
                  flexDirection: 'column',
                  height: '100%',
                  position: 'relative',
                }}
                data-testid={copilotChatPanelInnerID}
              >
                <Box
                  id="vertical-resize-click-target"
                  sx={{
                    position: 'absolute',
                    inset: 0,
                    height: '0.5rem',
                    width: '100%',
                    cursor: chatIsOpen ? 'ns-resize' : undefined,
                    // All these resizers gotta be 2 because Copilot messages are z-index: 1 and would overlap the resizers
                    zIndex: 2,
                  }}
                  onMouseDown={e => startResize(e, false, true)}
                />
                <Box
                  sx={{
                    position: 'absolute',
                    inset: 0,
                    height: '100%',
                    width: '8px',
                    cursor: chatIsOpen ? 'ew-resize' : undefined,
                    zIndex: 2,
                  }}
                  onMouseDown={e => startResize(e, true, false)}
                />
                <Box
                  sx={{
                    position: 'absolute',
                    inset: 0,
                    height: '0.5rem',
                    width: '0.5rem',
                    cursor: chatIsOpen ? 'nwse-resize' : 'undefined',
                    zIndex: 2,
                  }}
                  aria-label="Chat panel resizer"
                  aria-valuetext={`${panelWidth}, ${panelHeight}`}
                  aria-valuenow={panelWidth}
                  role="separator"
                  onMouseDown={e => startResize(e, true, true)}
                  tabIndex={0}
                  onKeyDown={onResizerKeyDown}
                />

                <Box sx={{display: 'flex', flexDirection: 'column', flexGrow: 1, maxHeight: '100%'}}>{children}</Box>
              </Box>
            </section>
          </ScopedCommands>
        </Overlay>
      ) : chatIsVisible && !isFeatureEnabled('copilot_no_floating_button') ? (
        <FloatingButton />
      ) : null}
    </>
  )
}
