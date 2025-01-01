import type {CopilotChatState} from '@github-ui/copilot-chat/utils/copilot-chat-reducer'

import {Layout} from './Layout'
import styles from './PipesPreviewArea.module.css'
import {PipesServiceProvider} from '../contexts/PipesServiceProvider'
import {PipesStateProvider} from '../contexts/PipesStateProvider'
import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import {CHAT_MODE_LOOPS, LOOP_SHARE_REGEX, REFERENCE_TYPE_LOOP} from '../utils/constants'
import {useSynchronizeLoop} from '../hooks/use-synchronize-loop'
import {AppContextProvider} from '../contexts/AppContextProvider'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {useCallback, useEffect} from 'react'
import {isPipesPlugin} from '../utils/plugin'
import type {LoopReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {setTitle} from '@github-ui/document-metadata'
import {useLocation, useParams} from 'react-router-dom'
import {SharedLoopImporter} from './SharedLoopImporter'
import {useLoop} from '../hooks/queries/use-loop'
import {getSelectedThread} from '@github-ui/copilot-chat/utils/get-selected-thread'

export interface PipesPreviewAreaProps {
  chatState: CopilotChatState
  plugin: ImmersivePlugin
}

export function PipesPreviewArea({chatState, plugin}: PipesPreviewAreaProps) {
  if (!isPipesPlugin(plugin)) throw new Error('PipesPreviewArea can only be used with a PipesPlugin')

  return (
    <PipesServiceProvider value={plugin.service}>
      <PipesPreviewAreaInner chatState={chatState} previewUrl={plugin.previewUrl} />
    </PipesServiceProvider>
  )
}

interface PipesPreviewAreaInnerProps {
  chatState: CopilotChatState
  previewUrl?: string
}

function PipesPreviewAreaInner({chatState, previewUrl}: PipesPreviewAreaInnerProps) {
  const {loopID} = useParams()

  const manager = useChatManager()
  const {currentReferences} = chatState
  const thread = getSelectedThread(chatState)
  const {data: loop} = useLoop()

  // hack to hide the header when viewing a loop
  useLayoutEffect(() => {
    const header = document.querySelector<HTMLElement>('header.AppHeader')
    if (header) {
      header.style.display = 'none'
    }

    return () => {
      if (header) {
        header.style.display = ''
      }
    }
  }, [])

  const sendChatMessage = useCallback(
    async (message: string) => {
      if (!loopID) return

      const trimmedContent = message.trim()
      if (trimmedContent === '') return

      let references = currentReferences
      if (loop) {
        const loopReference: LoopReference = {type: REFERENCE_TYPE_LOOP, ...loop}
        references = [...references, loopReference]
      }

      manager.sendChatMessage({
        thread,
        content: trimmedContent,
        modeOverride: CHAT_MODE_LOOPS,
        references,
      })
    },
    [loopID, currentReferences, loop, manager, thread],
  )

  return (
    <AppContextProvider
      availableModels={chatState.availableModels}
      previewUrl={previewUrl}
      sendChatMessage={sendChatMessage}
    >
      <PipesStateProvider>
        <PipesPreview chatState={chatState} />
      </PipesStateProvider>
    </AppContextProvider>
  )
}

function PipesPreview({chatState}: {chatState: CopilotChatState}) {
  useSynchronizeLoop(chatState)
  const {data: loop} = useLoop()
  const location = useLocation()
  const isSharedLoopRoute = LOOP_SHARE_REGEX.test(location.pathname)

  // Set the page title when component mounts
  useEffect(() => {
    const title = loop?.title ? `${loop.title} · Loops · GitHub Copilot` : 'Loops · GitHub Copilot'
    setTitle(title)
  }, [loop?.title])

  if (isSharedLoopRoute) {
    return <SharedLoopImporter />
  }

  return (
    <div className={styles.container}>
      <Layout />
    </div>
  )
}
