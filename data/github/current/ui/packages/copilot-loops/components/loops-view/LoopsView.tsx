import {LegalDisclaimer} from '@github-ui/copilot-chat/components/LegalDisclaimer'
import ServiceView from '@github-ui/copilot-chat/components/Service/ServiceView'
import styles from './LoopsView.module.css'
import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import {ChatInput} from '@github-ui/copilot-chat/components/ChatInput'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {useAllLoops} from '../../hooks/queries/use-all-loops'
import {useEffect} from 'react'
import {COPILOT_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {Icon} from '@github-ui/pacer/Icon'
import {isPipesPlugin} from '../../utils/plugin'
import {LoopsViewHeader} from './LoopsViewHeader'
import {staffExamples} from '../../example-loops/staff-examples'
import type {Pipeline} from '../../types/app'
import {setTitle} from '@github-ui/document-metadata'
import {useNavigate} from 'react-router-dom'
import {PipesServiceProvider, usePipesService} from '../../contexts/PipesServiceProvider'
import {LoopCard} from './LoopCard'
import {LoopExampleCard} from './LoopExampleCard'
import {sendEvent} from '@github-ui/hydro-analytics'
import {setLoopThreadId} from '../../utils/loop-thread-storage'

export interface LoopsViewProps {
  plugin?: ImmersivePlugin
}

export function LoopsView({plugin}: LoopsViewProps) {
  if (!plugin || !isPipesPlugin(plugin)) throw new Error('LoopsView can only be used with a PipesPlugin')

  return (
    <PipesServiceProvider value={plugin.service}>
      <LoopsViewInner />
    </PipesServiceProvider>
  )
}

function LoopsViewInner() {
  const {data: loops, isLoading} = useAllLoops()
  const manager = useChatManager()
  const navigate = useNavigate()
  const loopsService = usePipesService()

  useEffect(() => {
    // Set the page title when component mounts
    setTitle('Loops · GitHub Copilot')
  }, [])

  useEffect(() => {
    // clear out the thread on mount
    manager.selectThread(null, {includeThreads: false, clearTopic: true})
  }, [manager])

  const handleUserSubmit = async (content: string) => {
    const trimmedContent = content.trim()
    if (trimmedContent === '') return

    sendEvent('dotcom_chat.activate', {target: 'OVERVIEW_INITIAL_CREATE', mode: 'loops'})

    const newLoopId = crypto.randomUUID()

    const thread = await manager.createThread()
    await loopsService.createLoop(newLoopId)
    setLoopThreadId(newLoopId, thread.id)

    const chatMessageParams = {
      content: trimmedContent,
      references: [],
      thread,
    }

    manager.sendChatMessage(chatMessageParams)
    navigate(`${COPILOT_PATH}/l/${newLoopId}`)
  }

  const createThreadWithLoop = async (loop: Pipeline) => {
    await loopsService.createLoop(loop)
    navigate(`${COPILOT_PATH}/l/${loop.id}`)
  }

  return (
    <>
      <LoopsViewHeader />
      <ServiceView.Container>
        <div className={styles.header}>
          <ServiceView.Header>
            <ServiceView.Icon icon={<Icon icon="loops" size={32} />} />
            <ServiceView.Title>Automate once. Loop forever.</ServiceView.Title>
            <ServiceView.Description>
              Loops simplifies workflow automation by allowing you to define processes with clear inputs, prompts, and
              outputs—no manual setup required. Powered by Copilot, Loops makes it easy to automate and manage tasks,
              streamlining your operations with minimal effort.
            </ServiceView.Description>
          </ServiceView.Header>
          <div className={styles.input}>
            <ChatInput
              hideAttachmentButton
              placeholder="What would you like to automate?"
              size="large"
              onSubmit={handleUserSubmit}
            />
            <LegalDisclaimer />
          </div>
        </div>
        {isLoading || (loops && loops.length > 0) ? (
          <ServiceView.Section>
            <ServiceView.Section.Title>Your loops</ServiceView.Section.Title>
            <ServiceView.Section.Grid loading={isLoading}>
              {loops?.map(item => (
                <LoopCard
                  key={item.id}
                  item={item}
                  onClick={() =>
                    sendEvent('dotcom_chat.activate', {target: 'OVERVIEW_USER_LOOP_SELECT', mode: 'loops'})
                  }
                />
              ))}
            </ServiceView.Section.Grid>
          </ServiceView.Section>
        ) : null}
        <ServiceView.Section>
          <ServiceView.Section.Title>Examples</ServiceView.Section.Title>
          <ServiceView.Section.Grid loading={isLoading}>
            {staffExamples.map(({altText, assetPath, loop: exampleLoop}) => (
              <LoopExampleCard
                key={exampleLoop.title}
                altText={altText}
                assetPath={assetPath}
                exampleLoop={exampleLoop}
                onSelect={createThreadWithLoop}
              />
            ))}
          </ServiceView.Section.Grid>
        </ServiceView.Section>
      </ServiceView.Container>
    </>
  )
}
