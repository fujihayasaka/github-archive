import {isFeatureEnabled} from '@github-ui/feature-flags'
import {RepoIcon} from '@primer/octicons-react'
import {Box, Link, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import {isDocset, isRepository} from '../utils/copilot-chat-helpers'
import {CanIndexStatus, TopicIndexStatus, useReposIndexingState} from '../utils/copilot-chat-hooks'
import type {CopilotChatRepo, Docset} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState} from '../utils/CopilotChatContext'
import AllTopicsButton from './AllTopicsButton'
import {KnowledgeBaseAvatar} from './KnowledgeBaseAvatar'
import {RepoAvatar} from './RepoAvatar'
import {TopicIndexState} from './TopicIndexState'

export default function TopicIndexedMessage() {
  const {currentTopic, mode, messages} = useChatState()

  const isTopicDocset = isDocset(currentTopic)
  const isTopicRepo = isRepository(currentTopic)
  const isImmersiveV1 = mode === 'immersive' && copilotFeatureFlags.copilotImmersiveV1

  let currentTopicFullName = currentTopic?.name
  let nwo = null
  if (currentTopic && isTopicRepo) {
    nwo = `${currentTopic.ownerLogin}/${currentTopic.name}`
    currentTopicFullName = nwo
  }
  const topicNwos = isTopicDocset ? currentTopic.repos : nwo ? [nwo] : []
  const [indexingState, triggerIndexing] = useReposIndexingState(topicNwos)

  const okToIndex =
    indexingState.requestStatus === CanIndexStatus.CanIndex &&
    ((isTopicRepo && indexingState.code === TopicIndexStatus.Unindexed) ||
      (isTopicDocset && indexingState.docs === TopicIndexStatus.Unindexed))

  const cannotIndex =
    ((isTopicRepo && indexingState.code === TopicIndexStatus.Unindexed) ||
      (isTopicDocset && indexingState.docs === TopicIndexStatus.Unindexed)) &&
    indexingState.requestStatus !== CanIndexStatus.CanIndex

  const showIndexingState = isTopicRepo || isTopicDocset

  const exploreText = <p>Explore and learn about programming-related concepts using natural language.</p>

  const disclaimerText = (
    <Text as="p" sx={{mb: 0}}>
      Copilot is powered by AI, so mistakes are possible. Review output carefully before use.{' '}
      <Link
        inline
        href="https://docs.github.com/en/copilot/github-copilot-enterprise/copilot-chat-in-github/about-github-copilot-chat"
        target="_blank"
        rel="noopener noreferrer"
      >
        Learn more about GitHub Copilot Chat.
      </Link>
    </Text>
  )

  const helpText = !currentTopic ? (
    <span>
      {!isImmersiveV1 && exploreText}
      {!isImmersiveV1 && disclaimerText}
    </span>
  ) : isTopicDocset ? (
    <span>
      {currentTopic.description && <p>{currentTopic.description}</p>}
      <p>
        Knowledge bases allow you to chat with Copilot about docs content from multiple repositories using natural
        language questions like <i>&quot;How do I get started with ___?&quot;</i> or{' '}
        <i>&quot;Explain concept ___&quot;</i>.
      </p>
      {!isImmersiveV1 && disclaimerText}
    </span>
  ) : (
    <>
      {!copilotFeatureFlags.staticThreadSuggestions && (
        <p>
          You can ask questions like <i>&quot;What does this file do?&quot;</i> or{' '}
          <i>&quot;Where is this functionality defined?&quot;</i>
        </p>
      )}
      <Text sx={{mb: 0}}>{disclaimerText}</Text>
    </>
  )

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'start',
        gap: 2,
        color: isImmersiveV1 ? 'fg.muted' : 'fg.default',
        borderBottom: isImmersiveV1
          ? '1px solid var(--borderColor-muted, var(--color-border-muted))'
          : '1px solid var(--borderColor-default, var(--color-border-default))',
        marginBottom: isImmersiveV1 ? 3 : 0,
        paddingBottom: isImmersiveV1 ? 3 : 0,
      }}
    >
      {mode === 'immersive' && messages.length === 0 && <AllTopicsButton />}
      <Box
        sx={{
          display: 'flex',
          flexDirection: 'column',
          width: '100%',
        }}
      >
        <Box sx={{display: 'flex', alignItems: 'center', p: 3, pb: 0, gap: 2}}>
          {currentTopic && (
            <Box sx={{flexShrink: 0}}>
              {isTopicDocset ? (
                <KnowledgeBaseAvatar docset={currentTopic} size={32} />
              ) : (
                <RepoAvatar ownerLogin={currentTopic.ownerLogin} ownerType={currentTopic.ownerType} size={32} />
              )}
            </Box>
          )}
          <div>
            {!isImmersiveV1 && (
              <Box sx={{display: 'flex', gap: 2}}>
                <Text as="h1" sx={{fontSize: 2, lineHeight: 1.25, wordBreak: 'break-word'}}>
                  {currentTopic ? `Chatting about ${currentTopicFullName}` : 'Chatting about code and programming'}
                </Text>
              </Box>
            )}
            <Text sx={{fontSize: 0, color: 'fg.muted'}}>
              {currentTopic &&
                (!isTopicDocset ? (
                  <span>
                    <Text sx={{textTransform: 'capitalize'}}>{currentTopic?.visibility}</Text> repository
                  </span>
                ) : (
                  <span>{currentTopic?.visibleOutsideOrg ? 'Public' : 'Private'} knowledge base</span>
                ))}
            </Text>
          </div>
        </Box>
        <Box sx={{p: 3}}>{helpText}</Box>
        {isTopicDocset && (
          <Box sx={{p: 3, pt: 0}}>
            <Box sx={{color: 'fg.muted', fontWeight: 600, fontSize: 0}}>
              Repositories included in this knowledge base
            </Box>
            {currentTopic.repos.map(repo => (
              <Box key={repo} sx={{display: 'flex', alignItems: 'center', pt: 2, pb: 2, gap: 2}}>
                <Octicon icon={RepoIcon} sx={{color: 'fg.muted'}} />
                <Link href={`/${repo}`} sx={{color: 'fg.default'}}>
                  {repo}
                </Link>
              </Box>
            ))}
          </Box>
        )}
        {showIndexingState && (
          <TopicIndexState
            currentTopic={currentTopic}
            indexingState={indexingState}
            okToIndex={okToIndex}
            triggerIndexing={triggerIndexing}
          />
        )}
        {cannotIndex && (
          <CannotIndexReason
            canIndexStatus={indexingState.requestStatus}
            currentTopic={currentTopic}
            hitIndividualLimit={
              indexingState.remainingRepoIndexTokens !== undefined && indexingState.remainingRepoIndexTokens <= 0
            }
          />
        )}
      </Box>
    </Box>
  )
}

function CannotIndexReason({
  canIndexStatus,
  currentTopic,
  hitIndividualLimit,
}: {
  canIndexStatus: CanIndexStatus
  currentTopic: CopilotChatRepo | Docset | undefined
  hitIndividualLimit: boolean
}) {
  let reason
  switch (canIndexStatus) {
    case CanIndexStatus.Unauthorized:
      reason = <span>Ask an organization owner to have this repository indexed for semantic code search.</span>
      break
    case CanIndexStatus.Unknown:
      return null
    case CanIndexStatus.Forbidden:
      reason = <span>You can only index repositories that your organization owns.</span>
      break
    case CanIndexStatus.QuotaExhausted:
      reason = hitIndividualLimit ? (
        <span>You have reached your semantic search token limit. Please wait for more tokens to be granted.</span>
      ) : (
        <span>
          Your organization has reached its limit for semantic search indexing. Contact your GitHub representative to
          increase your limit.
          {isFeatureEnabled('COPILOT_SEMANTIC_CODE_SEARCH_SETTINGS') && (
            <>
              {' '}
              Organization administrators can{' '}
              <Link
                inline
                href={`/organizations/${
                  (currentTopic as CopilotChatRepo).ownerLogin
                }/settings/copilot/semantic_code_search`}
              >
                manage indexed repositories
              </Link>
              .
            </>
          )}
        </span>
      )
      break
    case CanIndexStatus.ServiceUnavailable:
      reason = (
        <>
          <Text sx={{fontWeight: 600}}>Indexing temporarily unavailable due to heavy load.</Text>
          <span>Please check back later.</span>
        </>
      )
      break
    default:
      return null
  }
  return (
    <Box
      sx={{
        p: 3,
        display: 'flex',
        alignItems: 'center',
        gap: 2,
        bg: 'canvas.subtle',
        borderRadius: '0 0 6px 6px',
        borderTop: '1px solid var(--borderColor-default, var(--color-border-default))',
      }}
    >
      {reason}
    </Box>
  )
}
