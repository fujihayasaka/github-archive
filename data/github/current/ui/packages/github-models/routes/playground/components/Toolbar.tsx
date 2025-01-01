import type {PropsWithChildren} from 'react'
import {IconButton, useResponsiveValue} from '@primer/react'
import {TrashIcon} from '@primer/octicons-react'
import {useSearchParams} from '@github-ui/use-navigate'
import {PlaygroundCodeLanguage} from './PlaygroundCodeLanguage'
import {PlaygroundCodeSDK} from './PlaygroundCodeSDK'
import {RestoreHistoryButton} from './RestoreHistoryButton'
import {AddModelButton} from './AddModelButton'
import type {ModelState} from '../../../types'
import {PlaygroundContentOption} from './types'
import {Panel, usePlaygroundManager} from '../../../utils/playground-manager'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import {useMessageHistory} from './MessageHistoryContext'

interface ToolbarProps extends PropsWithChildren {
  modelState: ModelState
  option: PlaygroundContentOption
  position: number
  onComparisonMode: boolean
  stopStreamingMessages: () => void
}

export const Toolbar = ({
  children,
  modelState,
  option,
  position,
  onComparisonMode,
  stopStreamingMessages,
}: ToolbarProps) => {
  const {models} = usePlaygroundState()
  const manager = usePlaygroundManager()
  const isMobile = useResponsiveValue({narrow: true}, false)
  const {messages, catalogData} = modelState
  const {history, setHistory} = useMessageHistory()
  const isComparable = !onComparisonMode
  const canRestoreHistory = history.length > 0 && messages.length === 0 && isComparable
  const [_, setSearchParams] = useSearchParams()

  const handleAddModel = async () => {
    const currentModelName = catalogData.name
    if (!currentModelName) return

    const mainModelState = models[Panel.Main]
    if (!mainModelState) return

    const forceSyncInputs = true
    manager.setSyncInputs(forceSyncInputs)
    const response = await manager.getSideModel(currentModelName, mainModelState, forceSyncInputs)
    if (!response.success) return

    setSearchParams({
      compare_to: currentModelName,
    })
  }

  const handleClearHistory = () => {
    stopStreamingMessages()
    manager.resetHistory(position)
    setHistory([])
  }

  const handleRestoreHistory = () => {
    manager.setMessages(position, history)
  }

  switch (option) {
    case PlaygroundContentOption.CHAT:
      return (
        <>
          {canRestoreHistory ? <RestoreHistoryButton onClick={handleRestoreHistory} /> : null}
          {isComparable && !isMobile && <AddModelButton models={models} onClick={handleAddModel} />}
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
          <PlaygroundCodeLanguage gettingStarted={modelState.gettingStarted} />
          <PlaygroundCodeSDK gettingStarted={modelState.gettingStarted} />
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
