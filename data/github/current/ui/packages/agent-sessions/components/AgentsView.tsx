import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {LegalDisclaimer} from '@github-ui/copilot-chat/components/LegalDisclaimer'
import {ChatInput} from '@github-ui/copilot-chat/components/ChatInput'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {setTitle} from '@github-ui/document-metadata'
import ServiceView from '@github-ui/copilot-chat/components/Service/ServiceView'
import {ListView} from '@github-ui/list-view'
import type {SessionItem} from '../types/session-item'
import {useEffect} from 'react'
import styles from './AgentsView.module.css'
import {AgentsTaskListItem} from './AgentsTaskListItem'
import {DependabotIcon} from '@primer/octicons-react'

type AppPayload = {
  agentSessions: SessionItem[]
}

export function AgentsView() {
  const manager = useChatManager()

  useEffect(() => {
    // Set the page title when component mounts
    setTitle('Agents · GitHub Copilot')
  }, [])

  useEffect(() => {
    // clear out the thread on mount
    manager.selectThread(null, {includeThreads: false, clearTopic: true})
  }, [manager])

  const handleUserSubmit = async (content: string) => {
    const trimmedContent = content.trim()
    if (trimmedContent === '') return
    manager.sendChatMessage({
      content: trimmedContent,
      thread: null,
      references: [],
    })
  }
  const {agentSessions} = useAppPayload<AppPayload>()
  return (
    <>
      <ServiceView.Container>
        <div className={styles.header}>
          <div className={styles.titleWrapper}>
            <ServiceView.Icon icon={<DependabotIcon size={32} />} />
            <h2 className={styles.title}>Agents at your service. Effortless productivity.</h2>
            <p className={styles.description}>
              Agents empower you to offload tasks and decisions to Copilot, automating your workflow while you focus on
              what matters most.
            </p>
          </div>
          <div className={styles.input}>
            <ChatInput
              hideAttachmentButton
              placeholder="Open a pull request in monalisa/my-website to add a light/dark mode switcher"
              size="large"
              onSubmit={handleUserSubmit}
            />
            <LegalDisclaimer />
          </div>
        </div>

        <ServiceView.Section>
          <div className={styles.listWrapper}>
            <ListView title="Pull Requests" titleHeaderTag="h2" className={styles.list}>
              {agentSessions.map(session => {
                const lastSession = session.sessions[session.sessions.length - 1]
                const lastSessionState = lastSession?.state
                const lastSessionStartDate = lastSession?.created_at
                return (
                  <AgentsTaskListItem
                    key={session.pull.id}
                    state={lastSessionState}
                    merged={session.pull.merged_at !== null}
                    lastSessionStartDate={lastSessionStartDate}
                    pullRequest={session.pull}
                    revisionCount={session.sessions.length}
                  />
                )
              })}
            </ListView>
          </div>
        </ServiceView.Section>
      </ServiceView.Container>
    </>
  )
}
