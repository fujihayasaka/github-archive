import {PlaygroundChat} from './PlaygroundChat'
import {PlaygroundInputs} from './PlaygroundInputs'
import {useCallback, useEffect, useState} from 'react'
import {modelPlaygroundPath} from '@github-ui/paths'
import {getDefaultUiState, setLocalStorageUiState} from '../../../utils/playground-local-storage'
import {useResponsiveValue} from '@primer/react'
import {PlaygroundHeader} from './PlaygroundHeader'
import {GiveFeedback} from '../../../components/GiveFeedback'
import {MessageHistoryProvider} from './MessageHistoryContext'
import ModelSwitcher from './ModelSwitcher'
import {useNavigate} from '@github-ui/use-navigate'
import {SidebarSelectionOptions} from '../../../types'
import type {ModelState} from '../../../types'
import {useModelClient} from '../contexts/ModelClientContext'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import {NoModel} from './NoModel'

export type PlaygroundProps = {
  modelState?: ModelState
  position: number
}

function assertSidebarSelectionOptions(value: number): asserts value is SidebarSelectionOptions {
  if (new Set<number>(Object.values(SidebarSelectionOptions)).has(value)) return
  throw new Error(`Invalid SidebarSelectionOptions "${value}"`)
}

export function Playground({modelState, position}: PlaygroundProps) {
  const storedDefaults = getDefaultUiState(modelState?.gettingStarted)
  const modelClient = useModelClient()
  const [showSidebarOnMobile, setShowSidebarOnMobile] = useState(false)
  const [uiState, setUiState] = useState(storedDefaults)
  const isMobile = useResponsiveValue({narrow: true}, false)
  const {models} = usePlaygroundState()
  const onComparisonMode = models.length > 1

  const navigate = useNavigate()

  const handleSetSidebarTab = (value: number) => {
    assertSidebarSelectionOptions(value)
    setLocalStorageUiState({...uiState, sidebarTab: value})
    setUiState(prevState => ({...prevState, sidebarTab: value}))
    setShowSidebarOnMobile(true)
  }

  const handleShowSidebar = (value: boolean) => {
    setUiState(prevState => ({...prevState, showSidebar: value}))
    setLocalStorageUiState({...uiState, showSidebar: value})
  }

  const handleSelectLanguage = useCallback(
    (language: string) => {
      const languageEntry = modelState?.gettingStarted[language]
      if (!languageEntry) return
      const availableSDK = Object.keys(languageEntry.sdks).includes(uiState.preferredSdk)
        ? uiState.preferredSdk
        : Object.keys(languageEntry.sdks)[0] || ''
      setUiState(prevState => ({...prevState, preferredLanguage: language, preferredSdk: availableSDK}))
      setLocalStorageUiState({
        ...uiState,
        preferredLanguage: language,
        preferredSdk: availableSDK,
      })
    },
    [modelState?.gettingStarted, uiState],
  )

  const handleSelectSDK = useCallback(
    (sdk: string) => {
      setUiState(prevState => ({...prevState, preferredSdk: sdk}))
      setLocalStorageUiState({
        ...uiState,
        preferredSdk: sdk,
      })
    },
    [uiState],
  )

  const stopStreamingMessages = useCallback(() => modelClient.stopStreamingMessages(position), [modelClient, position])

  // Stop streaming messages when the model changes
  useEffect(() => {
    return stopStreamingMessages
  }, [stopStreamingMessages, modelState?.catalogData?.name])

  return (
    <div className={`flex-1 d-flex flex-column height-fit`} style={{minWidth: onComparisonMode ? '560px' : undefined}}>
      {modelState ? (
        <PlaygroundHeader
          model={modelState?.catalogData}
          position={position}
          gettingStarted={modelState?.gettingStarted}
          uiState={uiState}
          setUiState={setUiState}
          handleSetSidebarTab={handleSetSidebarTab}
        />
      ) : (
        <div className="d-flex flex-justify-between mb-3">
          <ModelSwitcher
            onSelect={async m => navigate({pathname: modelPlaygroundPath(m)})}
            onComparisonMode={onComparisonMode}
            handleSetSidebarTab={handleSetSidebarTab}
          />
          {!isMobile && <GiveFeedback />}
        </div>
      )}
      <div
        className={`flex-1 d-flex flex-column flex-md-row border ${
          modelState ? 'overflow-hidden' : '' // we want to hide overflow only on the chat view, not the landing page
        } ${onComparisonMode ? 'rounded-bottom-2' : 'rounded-2'}`}
      >
        {modelState ? (
          <>
            <MessageHistoryProvider>
              <PlaygroundChat
                model={modelState}
                position={position}
                stopStreamingMessages={stopStreamingMessages}
                showSidebar={uiState.showSidebar}
                onComparisonMode={onComparisonMode}
                handleSetSidebarTab={handleSetSidebarTab}
                handleShowSidebar={handleShowSidebar}
                uiState={uiState}
                handleSelectLanguage={handleSelectLanguage}
                handleSelectSDK={handleSelectSDK}
              />
            </MessageHistoryProvider>
            {!onComparisonMode && (
              <PlaygroundInputs
                model={modelState}
                position={position}
                sidebarTab={uiState.sidebarTab}
                showSidebar={uiState.showSidebar}
                showSidebarOnMobile={showSidebarOnMobile}
                handleSetSidebarTab={handleSetSidebarTab}
                handleShowSidebar={handleShowSidebar}
                handleShowSidebarOnMobile={setShowSidebarOnMobile}
              />
            )}
          </>
        ) : (
          <NoModel />
        )}
      </div>
    </div>
  )
}
