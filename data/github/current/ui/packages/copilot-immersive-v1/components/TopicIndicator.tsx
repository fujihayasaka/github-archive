import {TopicIndicatorFlash} from '@github-ui/copilot-chat/components/TopicIndicatorFlash'
import {useChatStateLens} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {isRepository} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {TopicIndexStatus, useRepoIndexingState} from '@github-ui/copilot-chat/utils/copilot-chat-hooks'
import type {CopilotChatRepo, DocsetReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useQuery} from '@github-ui/react-query'
import {BookIcon, RepoIcon} from '@primer/octicons-react'
import {useCallback, useEffect, useRef} from 'react'

export function useCurrentTopic() {
  const repo = useChatStateLens(s => (isRepository(s.currentTopic) ? s.currentTopic : undefined))
  const docset = useChatStateLens(s => s.currentReferences.find(r => r.type === 'docset'))

  if (copilotFeatureFlags.topicsAsReferences) return null
  return repo ?? docset
}

function isDocset(topic: CopilotChatRepo | DocsetReference): topic is DocsetReference {
  return 'type' in topic && topic.type === 'docset'
}

interface TopicIndicatorProps {
  topic: CopilotChatRepo | DocsetReference
}

export function TopicIndicator({topic}: TopicIndicatorProps) {
  // Docsets (AKA knowledge bases AKA KBs because nothing is ever simple) are now stored in references rather than
  // topics. Which really means we should just render them as attachment tokens like all the other references instead
  // of pretending they are still a regular topic, but I digress.

  // What even is a topic anyway? Turns out it doesn't even exist in CAPI - it's just another thing that gets turned
  // into a reference. So why do we have topics? Maybe job security - can't afford to make anything too straightforward?

  // Currently there should only ever be one KB attached, so we'll just assume that there never will be more than one
  // in the future. I'm sure that's safe. Of course we could just render them as attachment tokens and not have to
  // worry about how many there are, but I digress again.
  return isDocset(topic) ? <KbTopicIndicator docset={topic} /> : <RepoTopicIndicator repo={topic} />
}

interface RepoTopicIndicatorProps {
  repo: CopilotChatRepo
}

function RepoTopicIndicator({repo}: RepoTopicIndicatorProps) {
  const indexingAllowed = useChatStateLens(s => s.model && !s.model.hasLimitedCapabilities)

  const nameWithOwner = `${repo.ownerLogin}/${repo.name}`

  const [indexingState, triggerIndexing] = useRepoIndexingState(nameWithOwner)

  const autoTriggeredIndexing = useRef(false)

  // We could probably safely ignore `indexingState.docs` since we're only dealing with repos. But at this point I'm
  // pretty sure if I remove anything Copilot will haunt my nightmares.
  const isNotIndexed =
    indexingState.code === TopicIndexStatus.Unindexed || indexingState.docs === TopicIndexStatus.Unindexed

  useEffect(
    function startIndexing() {
      if (!autoTriggeredIndexing.current && isNotIndexed && indexingAllowed) {
        autoTriggeredIndexing.current = true
        triggerIndexing()
      }
    },
    [indexingAllowed, isNotIndexed, triggerIndexing],
  )

  const removeButtonRef = useRef<HTMLButtonElement>(null)

  return <TopicIndicatorFlash icon={<RepoIcon />} topic={repo} removeButtonRef={removeButtonRef} />
}

interface KbTopicIndicatorProps {
  docset: DocsetReference
}

function KbTopicIndicator({docset}: KbTopicIndicatorProps) {
  const manager = useChatManager()
  const reference = useChatStateLens(s => s.currentReferences.find(r => r.type === 'docset' && r.id === docset.id))

  const removeReference = useCallback(() => manager.removeReference(reference), [manager, reference])

  // The docset we get from the references list does not necessarily contain the repos list, so we need to fetch
  // the full KB data and populate it
  const {status: requestStatus, data: fullDocset} = useQuery({
    queryKey: ['copilot-immersive-v1', 'docsets'],
    queryFn: async () => {
      const res = await manager.fetchKnowledgeBases()
      if (!res.ok) throw new Error(res.error)
      return res.payload
    },
    // Returning all docsets and then selecting the right one allows reusing the query across all docsets. Eventually
    // we could reuse this query everywhere we use docset data and then we'd only make the request one single time.
    select: kbs => kbs.find(kb => kb.id === docset.id),
  })

  // Remove knowledge base references if the knowledge base no longer exists on the server.
  // See: https://github.com/github/copilot-core-productivity/issues/1285
  useEffect(
    function removeIfNotFound() {
      // Only if the request succeeded; otherwise we might accidentally remove the reference just because the connection was offline, for example
      if (requestStatus === 'success' && fullDocset === undefined) removeReference()
    },
    [requestStatus, fullDocset, removeReference],
  )

  const removeButtonRef = useRef<HTMLButtonElement>(null)

  return fullDocset ? (
    <TopicIndicatorFlash icon={<BookIcon />} topic={fullDocset} removeButtonRef={removeButtonRef} />
  ) : null
}
