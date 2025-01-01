import {Link} from '@primer/react'
import {clsx} from 'clsx'

import {AGENT_PREFIX, useAvailableAgents} from '../utils/agents-helpers'
import styles from './UserMessage.module.css'

interface UserMessageProps {
  children: string
  className?: string
}

/**
 * @group 0 Optional non-empty agent slug if present.
 * @group 1 The rest of the message, excluding leading agent mention.
 */
// note: I did check and agent mentions must be locked to the exact start of the string. No leading whitespace allowed
const userMessageRegex = new RegExp(`^(?:${AGENT_PREFIX}(\\S+))?(.*)`, 's')

/** Renders a user message. For user messages we don't format Markdown but we do render agent mentions as links. */
export function UserMessage({children: content, className}: UserMessageProps) {
  const [, agentSlug, message = ''] = userMessageRegex.exec(content) ?? []
  return (
    <div className={clsx(styles.container, className)}>
      {agentSlug && <AgentLink slug={agentSlug} />}
      {message}
    </div>
  )
}

interface AgentLinkProps {
  slug: string
}

/** Renders as link with hovercard if slug is valid; otherwise renders as plain text. */
function AgentLink({slug: slug}: AgentLinkProps) {
  // By calling this hook inside AgentLink, we can delay fetching agents until there is a potential mention
  const {availableAgents} = useAvailableAgents()
  const withPrefix = `${AGENT_PREFIX}${slug}`

  const agent = availableAgents?.find(a => a.slug === slug)
  if (agent)
    return (
      <Link
        href={agent.integrationUrl}
        data-hovercard-url={`/integrations/${slug}/hovercard`}
        className="bgColor-accent-muted"
      >
        {withPrefix}
      </Link>
    )

  return withPrefix
}
