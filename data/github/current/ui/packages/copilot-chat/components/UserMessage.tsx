import {Link} from '@primer/react'
import {clsx} from 'clsx'
import {unified} from 'unified'

import {useAvailableAgents} from '../utils/agents-helpers'
import type {CopilotChatAgent} from '../utils/copilot-chat-types'
import {userMessageParser} from '../utils/user-message/user-message-parser'
import {hasPotentialAgentMention} from '../utils/user-message/user-message-utils'
import {useChatMessage} from './ChatMessageContext'
import styles from './UserMessage.module.css'

interface UserMessageProps {
  className?: string
  /** Optional invisible header value for screen readers */
  accessibleHeader?: string
}

/** Renders a user message. */
export function UserMessage({className, accessibleHeader}: UserMessageProps) {
  const {message} = useChatMessage()
  const text = message.content ?? ''

  // delay fetching agents until there is a potential mention
  const {availableAgents = []} = useAvailableAgents(hasPotentialAgentMention(text))

  const messageTree = unified()
    .use(userMessageParser, {references: message.references ?? [], agents: availableAgents})
    .parse(text)

  return (
    <>
      {accessibleHeader && <h3 className="sr-only">{accessibleHeader}</h3>}
      <div className={clsx(styles.container, className)}>
        {messageTree.children.map((node, i) => {
          switch (node.type) {
            case 'text':
              return node.value
            case 'agent-mention':
              return (
                <AgentLink key={i} agent={node.data.mentionedAgent}>
                  {node.value}
                </AgentLink>
              )
            case 'reference-mention':
              return node.data.mentionedReferenceId !== undefined ? (
                <span key={i} className={styles.mention}>
                  {node.value}
                </span>
              ) : (
                node.value
              )
          }
        })}
      </div>
    </>
  )
}

interface AgentLinkProps {
  agent: CopilotChatAgent
  children: string
}

/** Renders as link with hovercard if slug is valid; otherwise renders as plain text. */
function AgentLink({agent, children}: AgentLinkProps) {
  return (
    <Link
      href={agent.integrationUrl}
      data-hovercard-url={`/integrations/${agent.slug}/hovercard`}
      className={styles.mention}
    >
      {children}
    </Link>
  )
}
