import {announce} from '@github-ui/aria-live'
import {AlertIcon, ArrowLeftIcon, DotFillIcon} from '@primer/octicons-react'
import {Box, Button, IconButton, Link, Spinner, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {useCallback, useState} from 'react'

import {isDocset} from '../utils/copilot-chat-helpers'
import {CanIndexStatus, type IndexingState, TopicIndexStatus} from '../utils/copilot-chat-hooks'
import type {CopilotChatRepo, Docset} from '../utils/copilot-chat-types'

export interface TopicIndexStateProps {
  currentTopic: CopilotChatRepo | Docset
  indexingState: IndexingState
  okToIndex: boolean
  triggerIndexing: () => void
}

export function TopicIndexState({currentTopic, indexingState, okToIndex, triggerIndexing}: TopicIndexStateProps) {
  const [disabled, setDisabled] = useState(false)
  const [showLearnMore, setShowLearnMore] = useState(false)
  const [userInitiatedIndexing, setUserInitiatedIndexing] = useState(false)
  const triggerIndexingCallback = useCallback(() => {
    setUserInitiatedIndexing(true)
    setDisabled(true)
    triggerIndexing()
    announce('Indexing requested.')
  }, [triggerIndexing])
  const isTopicDocset = isDocset(currentTopic)
  const topicTypeDescription = isTopicDocset ? 'knowledge base' : 'repository'
  const indexedState = isTopicDocset ? indexingState.docs : indexingState.code

  return indexedState === TopicIndexStatus.Indexed ? (
    <>
      <Box sx={{px: 3, pb: 3}}>
        <IndexedState />
      </Box>
      {userInitiatedIndexing && (
        <Box sx={{borderTop: '1px solid', py: 2, borderColor: 'border.muted', textAlign: 'center'}}>
          You indexed this repository.
          {indexingState.remainingRepoIndexTokens !== undefined && (
            <span className="color-fg-muted">{` ${indexingState.remainingRepoIndexTokens} repositories remaining.`}</span>
          )}
        </Box>
      )}
    </>
  ) : (
    <Box
      className="indexed-state-container"
      sx={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        m: 3,
        mt: 0,
        p: 3,
        gap: 3,
        border: '1px solid',
        borderColor: 'border.default',
        borderRadius: '6px',
        textAlign: !showLearnMore ? 'center' : undefined,
      }}
    >
      {showLearnMore ? (
        <div className="d-flex">
          <IconButton
            icon={ArrowLeftIcon}
            onClick={() => setShowLearnMore(false)}
            aria-label="Go back."
            variant="invisible"
            className="mr-2"
            sx={{height: '16px', marginTop: '2px'}}
          />
          <p className="m-0">
            Under your plan, limited repositories can be concurrently indexed for natural language search.{' '}
            <Link
              inline
              href="https://docs.github.com/en/copilot/managing-copilot/managing-github-copilot-in-your-organization/customizing-copilot-for-your-organization/indexing-repositories-for-copilot-chat#about-indexing-repositories"
              target="_blank"
              rel="noopener noreferrer"
            >
              Learn more
            </Link>
          </p>
        </div>
      ) : (
        <>
          <IndexedStateInfo
            indexedState={indexedState}
            canIndexStatus={indexingState.requestStatus}
            topicType={topicTypeDescription}
            remainingRepoIndexTokens={
              topicTypeDescription === 'repository' ? indexingState.remainingRepoIndexTokens : undefined
            }
          />
          <div className="d-flex">
            {okToIndex && (
              <Button variant="primary" onClick={triggerIndexingCallback} disabled={disabled} className="mr-2">
                Index {currentTopic.name}
              </Button>
            )}
            {indexingState.code !== TopicIndexStatus.Unknown && (
              <Button onClick={() => setShowLearnMore(true)}>Learn more</Button>
            )}
          </div>
        </>
      )}
    </Box>
  )
}

function IndexedStateInfo({
  indexedState,
  canIndexStatus,
  topicType,
  remainingRepoIndexTokens,
}: {
  indexedState: TopicIndexStatus
  canIndexStatus: CanIndexStatus
  topicType: string
  remainingRepoIndexTokens?: number
}) {
  switch (indexedState) {
    case TopicIndexStatus.Indexing:
      return <IndexingInProgressState topicType={topicType} remainingRepoIndexTokens={remainingRepoIndexTokens} />
    case TopicIndexStatus.Indexed:
      return <IndexedState />
    case TopicIndexStatus.Unindexed:
      return (
        <NotIndexedState
          canIndexStatus={canIndexStatus}
          topicType={topicType}
          remainingRepoIndexTokens={remainingRepoIndexTokens}
        />
      )
    default:
      return <LoadingState topicType={topicType} />
  }
}

function NotIndexedState({
  canIndexStatus,
  topicType,
  remainingRepoIndexTokens,
}: {
  canIndexStatus: CanIndexStatus
  topicType: string
  remainingRepoIndexTokens?: number
}) {
  switch (canIndexStatus) {
    case CanIndexStatus.Requested:
      return <IndexingInProgressState topicType={topicType} remainingRepoIndexTokens={remainingRepoIndexTokens} />
    case CanIndexStatus.RequestFailed:
      return (
        <Box sx={{display: 'flex', gap: 2, alignItems: 'center'}}>
          <Octicon icon={AlertIcon} size={16} sx={{color: 'fg.muted'}} />
          <div>
            <Text sx={{ml: 2}} aria-live="polite">
              Unable to queue for semantic indexing right now — try again later.
            </Text>
          </div>
        </Box>
      )
    default:
      return (
        <div className="d-flex flex-direction-v flex-column">
          {canIndexStatus === CanIndexStatus.CanIndex ? (
            <span>{`Unlock natural language search and improve Copilot's understanding by indexing this ${topicType}.`}</span>
          ) : (
            <span>This {topicType} is not currently indexed.</span>
          )}
          {remainingRepoIndexTokens !== undefined && canIndexStatus !== CanIndexStatus.Forbidden && (
            <span className="color-fg-muted">{`${remainingRepoIndexTokens} repositories remaining.`}</span>
          )}
        </div>
      )
  }
}

function IndexingInProgressState({
  topicType,
  remainingRepoIndexTokens,
}: {
  topicType: string
  remainingRepoIndexTokens?: number
}) {
  return (
    <Box sx={{display: 'flex', gap: 1, flexDirection: 'column', alignItems: 'center'}}>
      <span aria-live="polite">Copilot is indexing this {topicType}.</span>
      {remainingRepoIndexTokens !== undefined && (
        <span className="color-fg-muted">{`${remainingRepoIndexTokens} repositories remaining.`}</span>
      )}
      <div className="d-flex">
        <Spinner size="small" sx={{color: 'fg.muted'}} />
        <span className="ml-2">This may take a few minutes.</span>
      </div>
    </Box>
  )
}

function IndexedState() {
  return (
    <Box sx={{display: 'flex', alignItems: 'center'}}>
      <Octicon icon={DotFillIcon} size={16} sx={{color: 'success.fg'}} />
      <Box sx={{color: 'fg.muted', fontSize: 0, ml: 1}}>Indexed for improved understanding and accuracy.</Box>
    </Box>
  )
}

function LoadingState({topicType}: {topicType: string}) {
  return (
    <Box sx={{display: 'flex', gap: 3, alignItems: 'center'}}>
      <Spinner size="small" sx={{color: 'fg.muted', flexShrink: 0}} />
      <span>Checking for semantic {topicType === 'repository' ? 'code' : ''} search availability…</span>
    </Box>
  )
}
