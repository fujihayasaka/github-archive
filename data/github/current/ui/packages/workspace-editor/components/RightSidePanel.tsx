import type {IFileSyncerClient} from '@github/codespaces-lsp'
import {ScreenSize, useScreenSize} from '@github-ui/screen-size'
import {XIcon} from '@primer/octicons-react'
import {IconButton, Overlay, PageLayout} from '@primer/react'
import type React from 'react'
import {memo, useEffect, useRef} from 'react'

import {useWorkspaceEditorUIDispatch, useWorkspaceEditorUIState} from '../contexts/WorkspaceEditorUIContext'
import type {ConnectedCodespaceData} from '../utilities/workspace-editor-types'
import {RightPanelType} from '../utilities/workspace-editor-ui-reducer'
import type {ChatContainerProps} from './ChatPanel'
import {ChatContainer, ChatContent, ChatHeader} from './ChatPanel'
import styles from './RightSidePanel.module.css'
import type {SuggestionProps} from './SuggestionPanel'
import SuggestionPanel from './SuggestionPanel'
import {SuggestionPanelHeader} from './SuggestionPanelHeader'

interface BaseRightSidePanelProps {
  codespaceData?: ConnectedCodespaceData
  getFileSyncerClient: () => IFileSyncerClient | null
  panelType: string
}

type RightSidePanelProps = BaseRightSidePanelProps & ChatContainerProps & SuggestionProps

const ContainerComponent = ({children, panelType}: React.PropsWithChildren<RightSidePanelProps>) => {
  switch (panelType) {
    case RightPanelType.Chat:
      return <ChatContainer>{children}</ChatContainer>
    default:
      return children
  }
}

type CloseButtonProps = Pick<RightSidePanelProps, 'panelType'> & {
  buttonRef: React.RefObject<HTMLButtonElement>
  onClose: () => void
}

const CloseButton = ({buttonRef, onClose, panelType}: CloseButtonProps) => {
  return (
    <IconButton
      aria-label={`Close ${panelType} panel`}
      icon={XIcon}
      ref={buttonRef}
      variant="invisible"
      onClick={onClose}
    />
  )
}

export const RightSidePanel = memo(function RightSidePanel(props: Omit<RightSidePanelProps, 'panelType'>) {
  const {rightPanel} = useWorkspaceEditorUIState()
  const dispatch = useWorkspaceEditorUIDispatch()
  const {screenSize} = useScreenSize()
  const panelCloseRefButton = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    const timeout = window.setTimeout(() => panelCloseRefButton?.current?.focus())
    return () => {
      window.clearTimeout(timeout)
    }
  }, [rightPanel])

  const handleClose = () => dispatch({type: 'CLOSE_RIGHT_PANEL'})

  const subProps = {...props, panelType: rightPanel}

  let header: JSX.Element | null = null
  let content: JSX.Element | null = null
  switch (subProps.panelType) {
    case RightPanelType.Chat:
      header = <ChatHeader />
      content = (
        <div className="height-full overflow-y-auto d-flex flex-column">
          <ChatContent />
        </div>
      )
      break
    case RightPanelType.Suggestions:
      header = <SuggestionPanelHeader />
      content = <SuggestionPanel codespaceData={props.codespaceData} getFileSyncerClient={props.getFileSyncerClient} />
      break
    default:
      content = null
      break
  }

  const panelContent = (
    <ContainerComponent {...subProps}>
      <div className={styles.rightSidePanel}>
        <div className="d-flex flex-row flex-justify-between flex-items-center border-bottom border-default p-2">
          {header}
          <div className="flex-shrink-0">
            <CloseButton {...subProps} buttonRef={panelCloseRefButton} onClose={handleClose} />
          </div>
        </div>
        {content}
      </div>
    </ContainerComponent>
  )

  const isSmallScreen = screenSize < ScreenSize.medium
  const isOpen = rightPanel !== RightPanelType.None
  const showPanel = isOpen && screenSize >= ScreenSize.large
  const showOverlay = isOpen && !showPanel
  const overlayLeftProperty = !isSmallScreen ? 'var(--base-size-8)' : undefined
  const overlayTopProperty = !isSmallScreen ? '15vh' : undefined

  return (
    <>
      <PageLayout.Pane
        position="end"
        resizable
        hidden={!showPanel}
        padding="none"
        sx={{
          height: 'var(--workspace-editor-content-height)',
        }}
        width={{
          min: '360px',
          default: '400px',
          max: '600px',
        }}
      >
        {panelContent}
      </PageLayout.Pane>
      {showOverlay && (
        <Overlay
          returnFocusRef={panelCloseRefButton}
          onClickOutside={handleClose}
          onEscape={handleClose}
          top={overlayTopProperty}
          left={overlayLeftProperty}
          position="fixed"
          sx={{
            height: overlayTopProperty ? `calc(100vh - ${overlayTopProperty})` : '100vh',
            maxHeight: overlayTopProperty ? `calc(100vh - ${overlayTopProperty})` : '100vh',
            width: overlayLeftProperty ? `calc(100vw - (2 * ${overlayLeftProperty}))` : '100vw',
            borderRadius: isSmallScreen ? 0 : undefined,
          }}
        >
          <>{panelContent}</>
        </Overlay>
      )}
    </>
  )
})
