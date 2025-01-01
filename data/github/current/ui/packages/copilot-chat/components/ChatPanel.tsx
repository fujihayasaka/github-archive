import {isFeatureEnabled} from '@github-ui/feature-flags'
import {Box, Overlay} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {useCallback, useEffect, useRef} from 'react'

import {copilotChatHeaderButtonID, copilotChatPanelID, copilotChatPanelInnerID} from '../utils/constants'
import {MIN_PANEL_HEIGHT, MIN_PANEL_WIDTH} from '../utils/copilot-chat-hooks'
import type {DialogType} from '../utils/copilot-chat-types'
import {useChatState} from '../utils/CopilotChatContext'
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
  const {chatIsOpen, chatIsVisible, ...state} = useChatState()
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
        </Overlay>
      ) : chatIsVisible && !isFeatureEnabled('copilot_no_floating_button') ? (
        <FloatingButton />
      ) : null}
    </>
  )
}
