import {Box, Overlay} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {useCallback, useRef} from 'react'

import {MIN_PANEL_HEIGHT, MIN_PANEL_WIDTH} from '../utils/copilot-chat-hooks'
import type {DialogType} from '../utils/copilot-chat-types'
import {ChatPanelReferenceContext, useChatState} from '../utils/CopilotChatContext'
import styles from './ChatPanel.module.css'
import FloatingButton from './FloatingButton'
import {COPILOT_CHAT_PORTAL_ROOT} from './PortalContainerUtils'

interface ChatPanelProps {
  entrypointRef: React.RefObject<HTMLButtonElement>
  handleClose: (usedEscapeKey?: boolean) => void
  staffDialogRef: React.MutableRefObject<HTMLDivElement | null>
  children: React.ReactNode
  showStaffDialog: DialogType
  panelWidth: number
  panelHeight: number
  startResize: (e: React.MouseEvent, horizontal: boolean, vertical: boolean) => void
  onResizerKeyDown: (e: React.KeyboardEvent) => void
}

export const ChatPanel = (props: ChatPanelProps) => {
  const {children, entrypointRef, staffDialogRef, handleClose, panelWidth, panelHeight, startResize, onResizerKeyDown} =
    props
  const overlayRef = useRef<HTMLDivElement>(null)
  const {chatIsOpen, chatIsVisible} = useChatState()

  const onEscape = useCallback(() => {
    if (overlayRef.current && overlayRef.current.contains(document.activeElement)) {
      handleClose(true)
    }
  }, [handleClose])

  return (
    <>
      {chatIsOpen ? (
        <Overlay
          id="copilot-chat-panel"
          className={clsx(styles.copilotChatPanel)}
          ref={overlayRef}
          portalContainerName={COPILOT_CHAT_PORTAL_ROOT}
          onEscape={onEscape}
          onClickOutside={() => {}}
          ignoreClickRefs={[staffDialogRef as React.RefObject<HTMLDivElement>]}
          returnFocusRef={entrypointRef}
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
          preventFocusOnOpen
          position="fixed"
          role="dialog"
          aria-labelledby="copilot-chat-panel-inner"
        >
          <section id="copilot-chat-panel-inner" aria-label="Copilot chat panel" style={{height: '100%'}}>
            <Box
              sx={{
                display: 'flex',
                flexDirection: 'column',
                height: '100%',
                position: 'relative',
              }}
              data-testid="copilot-chat-panel-inner"
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

              <Box sx={{display: 'flex', flexDirection: 'column', flexGrow: 1, maxHeight: '100%'}}>
                <ChatPanelReferenceContext.Provider value={overlayRef}>{children}</ChatPanelReferenceContext.Provider>
              </Box>
            </Box>
          </section>
        </Overlay>
      ) : chatIsVisible ? (
        <FloatingButton />
      ) : null}
    </>
  )
}
