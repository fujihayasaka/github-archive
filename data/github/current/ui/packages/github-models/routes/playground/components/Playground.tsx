import {PlaygroundChat} from './PlaygroundChat'
import {PlaygroundInputs} from './PlaygroundInputs'
import type {ModelState, SidebarSelectionOptions} from '../../../types'
import {useCallback, useEffect, useState} from 'react'
import {Panel, type PlaygroundManager, usePlaygroundManager} from '../../../utils/playground-manager'
import type {ModelPersistentUIState} from '../../../utils/playground-local-storage'
import {Box, useResponsiveValue} from '@primer/react'
import {PlaygroundHeader} from './GettingStartedDialog/PlaygroundHeader'
import {GiveFeedback} from './GettingStartedDialog/GiveFeedback'
import type {AzureModelClient} from '../../../utils/azure-model-client'
import {MessageHistoryProvider} from './MessageHistoryContext'

const updateUiState = (manager: PlaygroundManager, newUiState: Partial<ModelPersistentUIState>) => {
  manager.localStorage.uiState = {
    ...manager.localStorage.uiState,
    ...newUiState,
  }
}

export type PlaygroundProps = {
  modelState: ModelState
  position: number
  onComparisonMode: boolean
  canUseO1Models: boolean
  modelClient: AzureModelClient
}

export function Playground({modelState, position, onComparisonMode, canUseO1Models, modelClient}: PlaygroundProps) {
  const {gettingStarted, modelInputSchema, catalogData} = modelState
  const manager = usePlaygroundManager()
  const storedDefaults = manager.localStorage.uiState

  // We currently do not support comparison view for mobile device
  const isMobile = useResponsiveValue({narrow: true}, false)
  if (isMobile && position === Panel.Side) {
    manager.removeModel(position)
  }

  const [sidebarTab, setSidebarTab] = useState(storedDefaults.sidebarTab)
  const [showSidebar, setShowSidebar] = useState(storedDefaults.showSidebar)
  const [showSidebarOnMobile, setShowSidebarOnMobile] = useState(false)

  const handleSetSidebarTab = useCallback(
    (value: SidebarSelectionOptions) => {
      updateUiState(manager, {sidebarTab: value})
      setSidebarTab(value)
      setShowSidebarOnMobile(true)
    },
    [manager],
  )

  const handleShowSidebar = (value: boolean) => {
    updateUiState(manager, {showSidebar: value})
    setShowSidebar(value)
  }

  const stopStreamingMessages = useCallback(() => modelClient.stopStreamingMessages(position), [modelClient, position])

  // Stop streaming messages when the model changes
  useEffect(() => {
    return stopStreamingMessages
  }, [stopStreamingMessages, modelState.catalogData.name])

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        height: 'calc(100dvh - 64px)',
        minWidth: onComparisonMode ? '560px' : undefined, // This is required for Safari
        flex: 1,
      }}
    >
      <Box
        sx={{
          display: ['block', 'block', 'none'],
        }}
      >
        <GiveFeedback mobile />
      </Box>
      <Box sx={{height: '100%', width: '100%', p: 3, overflow: 'auto'}}>
        <Box
          sx={{
            display: 'flex',
            flexDirection: 'column',
            flex: 1,
            width: '100%',
            height: '100%',
          }}
        >
          <Box
            sx={{
              flex: 1,
              display: 'flex',
              flexDirection: 'column',
              width: '100%',
              maxHeight: '100%',
              height: '100%',
            }}
          >
            <PlaygroundHeader
              model={catalogData}
              modelInputSchema={modelInputSchema}
              canUseO1Models={canUseO1Models}
              position={position}
              gettingStarted={gettingStarted}
              handleSetSidebarTab={handleSetSidebarTab}
            />
            <div
              className={`flex-1 d-flex flex-column flex-md-row border overflow-hidden ${
                onComparisonMode ? 'rounded-bottom-2' : 'rounded-2'
              }`}
            >
              <MessageHistoryProvider>
                <PlaygroundChat
                  model={modelState}
                  position={position}
                  modelClient={modelClient}
                  stopStreamingMessages={stopStreamingMessages}
                  showSidebar={showSidebar}
                  onComparisonMode={onComparisonMode}
                  handleSetSidebarTab={handleSetSidebarTab}
                  handleShowSidebar={handleShowSidebar}
                />
              </MessageHistoryProvider>
              {!onComparisonMode && (
                <PlaygroundInputs
                  model={modelState}
                  position={position}
                  sidebarTab={sidebarTab}
                  showSidebar={showSidebar}
                  showSidebarOnMobile={showSidebarOnMobile}
                  handleSetSidebarTab={handleSetSidebarTab}
                  handleShowSidebar={handleShowSidebar}
                  handleShowSidebarOnMobile={setShowSidebarOnMobile}
                />
              )}
            </div>
          </Box>
        </Box>
      </Box>
    </Box>
  )
}
