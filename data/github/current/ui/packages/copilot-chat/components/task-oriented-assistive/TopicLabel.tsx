import {referenceName} from '../../utils/copilot-chat-helpers'
import type {CopilotChatRepo, RepositoryReference} from '../../utils/copilot-chat-types'
import {iconForReference} from '../ReferenceToken'

export function TopicLabel({topic}: {topic?: CopilotChatRepo}): JSX.Element | undefined {
  if (!topic) {
    return undefined
  }

  // Coerce the topic to a reference type so we can leverage existing helpers
  // TODO as we support non-repository topics, handle them here
  const reference: RepositoryReference = {type: 'repository', ...topic}

  const Icon = iconForReference(reference, false)
  const name = referenceName(reference)

  return (
    <>
      {Icon && <Icon className="mr-1" size="small" />}
      <span className="flex-1">{name}</span>
    </>
  )
}
