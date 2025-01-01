import type {PropsWithChildren} from 'react'
import {IconButton} from '@primer/react'
import {TrashIcon} from '@primer/octicons-react'
import {PlaygroundCodeLanguage} from './PlaygroundCodeLanguage'
import {PlaygroundCodeSDK} from './PlaygroundCodeSDK'
import {RestoreHistoryButton} from './RestoreHistoryButton'
import type {ModelState} from '../../../types'
import {PlaygroundContentOption} from './types'
import {usePlaygroundManager} from '../../../contexts/PlaygroundManagerContext'
import {useMessageHistory} from './MessageHistoryContext'
import type {ModelPersistentUIState} from '../../../utils/playground-local-storage'

export interface ToolbarProps extends PropsWithChildren {
  modelState: ModelState
  option: PlaygroundContentOption
  position: number
  onComparisonMode: boolean
  uiState: ModelPersistentUIState
  handleSelectLanguage: (language: string) => void
  handleSelectSDK: (sdk: string) => void
  handleClearHistory: () => void
}

export const Toolbar = ({
  children,
  modelState,
  option,
  position,
  onComparisonMode,
  uiState,
  handleSelectLanguage,
  handleSelectSDK,
  handleClearHistory,
}: ToolbarProps) => {
  const manager = usePlaygroundManager()
  const {messages} = modelState
  const {history} = useMessageHistory()
  const isComparable = !onComparisonMode
  const canRestoreHistory = history.messages.length > 0 && messages.length === 0 && isComparable

  const handleRestoreHistory = () => {
    manager.setMessages(position, history.messages)
    manager.setTokenUsage(position, history.tokenUsage)
  }

  switch (option) {
    case PlaygroundContentOption.CHAT:
      return (
        <>
          {canRestoreHistory ? <RestoreHistoryButton onClick={handleRestoreHistory} /> : null}
          <IconButton
            icon={TrashIcon}
            size="small"
            aria-label="Reset chat history"
            disabled={messages.length === 0}
            onClick={handleClearHistory}
          />
        </>
      )
    case PlaygroundContentOption.CODE: {
      return (
        <>
          <PlaygroundCodeLanguage
            gettingStarted={modelState.gettingStarted}
            preferredLanguage={uiState.preferredLanguage}
            handleSelectLanguage={handleSelectLanguage}
          />
          <PlaygroundCodeSDK
            gettingStarted={modelState.gettingStarted}
            uiState={uiState}
            handleSelectSDK={handleSelectSDK}
          />
        </>
      )
    }
    case PlaygroundContentOption.JSON: {
      return (
        <>
          {canRestoreHistory ? <RestoreHistoryButton onClick={handleRestoreHistory} /> : null}
          {children}
        </>
      )
    }
  }
}
