import {announce} from '@github-ui/aria-live'
import {useChatStateLens, useChatStateValue} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {isFileReference, isRepository, isSnippetReference} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {CanIndexStatus, TopicIndexStatus, useRepoIndexingState} from '@github-ui/copilot-chat/utils/copilot-chat-hooks'
import type {CopilotChatRepo, DocsetReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {BookIcon, CheckIcon, CodescanIcon, KebabHorizontalIcon, RepoIcon, XIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, Link, Spinner} from '@primer/react'
import {useQuery} from '@tanstack/react-query'
import {clsx} from 'clsx'
import {type RefObject, useCallback, useEffect, useRef} from 'react'

import {useBooleanState} from '../hooks/use-boolean-state'
import {IndexingConfirmationDialog} from './IndexingConfirmationDialog'
import {IndexingUnavailableDialog} from './IndexingUnavailableDialog'
import {KnowledgeBaseInfoDialog} from './KnowledgeBaseInfoDialog'
import styles from './TopicIndicator.module.css'

export function TopicIndicator() {
  const repo = useChatStateLens(s => (isRepository(s.currentTopic) ? s.currentTopic : undefined))
  const docset = useChatStateLens(s => s.currentReferences.find(r => r.type === 'docset'))

  if (repo) return <RepoTopicIndicator repo={repo} />

  // Docsets (AKA knowledge bases AKA KBs because nothing is ever simple) are now stored in references rather than
  // topics. Which really means we should just render them as attachment tokens like all the other references instead
  // of pretending they are still a regular topic, but I digress.

  // What even is a topic anyway? Turns out it doesn't even exist in CAPI - it's just another thing that gets turned
  // into a reference. So why do we have topics? Maybe job security - can't afford to make anything too straightforward?

  // Currently there should only ever be one KB attached, so we'll just assume that there never will be more than one
  // in the future. I'm sure that's safe. Of course we could just render them as attachment tokens and not have to
  // worry about how many there are, but I digress again.
  if (docset) return <KbTopicIndicator docset={docset} />

  return null
}

interface RepoTopicIndicatorProps {
  repo: CopilotChatRepo
}

function RepoTopicIndicator({repo}: RepoTopicIndicatorProps) {
  const manager = useChatManager()

  const indexingAllowed = useChatStateLens(s => s.model && !s.model.hasLimitedCapabilities)
  const currentReferences = useChatStateValue('currentReferences')
  const selectedThreadID = useChatStateValue('selectedThreadID')

  const nameWithOwner = `${repo.ownerLogin}/${repo.name}`

  const [indexingState, triggerIndexing] = useRepoIndexingState(nameWithOwner)

  // We could probably safely ignore `indexingState.docs` since we're only dealing with repos. But at this point I'm
  // pretty sure if I remove anything Copilot will haunt my nightmares.
  const isIndexing =
    indexingState.code === TopicIndexStatus.Indexing || indexingState.docs === TopicIndexStatus.Indexing
  const isIndexed = indexingState.code === TopicIndexStatus.Indexed && indexingState.docs === TopicIndexStatus.Indexed
  const isNotIndexed =
    indexingState.code === TopicIndexStatus.Unindexed || indexingState.docs === TopicIndexStatus.Unindexed

  const [indexDialogOpen, openIndexDialog, closeIndexDialog] = useBooleanState(false)

  const triggerIndexingCallback = useCallback(() => {
    triggerIndexing()
    announce('Indexing requested.')
    closeIndexDialog()
  }, [triggerIndexing, closeIndexDialog])

  const hitIndividualLimit =
    indexingState.remainingRepoIndexTokens !== undefined && indexingState.remainingRepoIndexTokens <= 0

  const detachTopic = () => {
    copilotLocalStorage.setSelectedTopic(selectedThreadID ?? '', null)
    manager.clearCurrentTopic()

    // remove references to files in this repo
    const removeIndexes = [] as number[]
    for (const [i, reference] of currentReferences.entries()) {
      if ((isFileReference(reference) || isSnippetReference(reference)) && reference.repoID === repo.id) {
        removeIndexes.push(i)
      }
    }
    manager.removeReferences(removeIndexes)
  }

  const startIndexingButtonRef = useRef<HTMLButtonElement>(null)
  const removeButtonRef = useRef<HTMLButtonElement>(null)

  return (
    <>
      <TopicIndicatorFlash
        className={clsx(isIndexed && styles.containerIsIndexed, isIndexing && styles.containerIsIndexing)}
        icon={
          <>
            <div className={styles.mobileOnly}>{isIndexing ? <Spinner size="small" /> : <RepoIcon />}</div>
            <div className={styles.nonMobileOnly}>
              <RepoIcon />
            </div>
          </>
        }
        topic={nameWithOwner}
        nonMobileStatus={
          indexingAllowed && (
            <>
              {isIndexing && (
                <>
                  <Spinner size="small" />
                  <span className={styles.indexingStatus}>Indexing the repository; this may take a few minutes</span>
                </>
              )}
              {isIndexed && (
                <>
                  <CheckIcon />
                  <span className={styles.indexingStatus}>Repository analyzed for more accurate responses</span>
                </>
              )}
              {isNotIndexed && (
                <span className={styles.indexingStatus}>
                  Improve the accuracy of code responses.{' '}
                  <Link
                    className={styles.indexingCTA}
                    as="button"
                    muted
                    inline
                    data-testid="trigger-button"
                    onClick={openIndexDialog}
                    ref={startIndexingButtonRef}
                  >
                    Get started
                  </Link>
                </span>
              )}
            </>
          )
        }
        mobileActions={
          isNotIndexed && (
            <ActionMenu>
              <ActionMenu.Anchor>
                <IconButton icon={KebabHorizontalIcon} aria-label="Settings" variant="invisible" size="small" />
              </ActionMenu.Anchor>
              <ActionMenu.Overlay width="auto" side="outside-top">
                <ActionList>
                  <ActionList.Item onSelect={openIndexDialog}>
                    <ActionList.LeadingVisual>
                      <CodescanIcon />
                    </ActionList.LeadingVisual>
                    Index repository&hellip;
                  </ActionList.Item>
                  <ActionList.Item onSelect={detachTopic}>
                    <ActionList.LeadingVisual>
                      <XIcon />
                    </ActionList.LeadingVisual>
                    Remove topic
                  </ActionList.Item>
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          )
        }
        onRemove={detachTopic}
        removeButtonRef={removeButtonRef}
      />
      {indexDialogOpen &&
        (indexingState.requestStatus === CanIndexStatus.CanIndex ? (
          <IndexingConfirmationDialog
            topic={repo}
            onCancel={closeIndexDialog}
            onConfirm={triggerIndexingCallback}
            remainingRepoIndexTokens={indexingState.remainingRepoIndexTokens}
            // Can't return focus to the start indexing button because indexing will have started, removing that button
            returnFocusRef={removeButtonRef}
          />
        ) : (
          <IndexingUnavailableDialog
            status={indexingState.requestStatus}
            onClose={closeIndexDialog}
            hitIndividualLimit={hitIndividualLimit}
            returnFocusRef={startIndexingButtonRef}
          />
        ))}
    </>
  )
}

interface KbTopicIndicatorProps {
  docset: DocsetReference
}

function KbTopicIndicator({docset}: KbTopicIndicatorProps) {
  const manager = useChatManager()
  const referenceIndex = useChatStateLens(s =>
    s.currentReferences.findIndex(r => r.type === 'docset' && r.id === docset.id),
  )

  const [repoListVisible, showRepoList, hideRepoList] = useBooleanState(false)

  const removeReference = useCallback(() => manager.removeReference(referenceIndex), [manager, referenceIndex])

  // The docset we get from the references list does not necessarily contain the repos list, so we need to fetch
  // the full KB data and populate it
  const {status: requestStatus, data: fullDocset} = useQuery({
    queryKey: ['docsets'],
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

  const linkRef = useRef<HTMLButtonElement>(null)

  return (
    <>
      <TopicIndicatorFlash
        icon={<BookIcon />}
        topic={
          <>
            {docset.name}
            {fullDocset && (
              <>
                {' '}
                (
                <Link as="button" ref={linkRef} onClick={showRepoList} inline muted>
                  {fullDocset.repos.length} {fullDocset.repos.length === 1 ? 'repository' : 'repositories'}
                </Link>
                )
              </>
            )}
          </>
        }
        onRemove={removeReference}
      />
      {repoListVisible && fullDocset && (
        <KnowledgeBaseInfoDialog docset={fullDocset} onClose={hideRepoList} returnFocusRef={linkRef} />
      )}
    </>
  )
}

interface TopicIndicatorFlashProps {
  icon: React.ReactNode
  topic: React.ReactNode
  /** Only shown on large screens. */
  nonMobileStatus?: React.ReactNode
  /** Only shown on small screens. */
  mobileActions?: React.ReactNode
  onRemove: () => void
  className?: string
  removeButtonRef?: RefObject<HTMLButtonElement>
}

function TopicIndicatorFlash({
  icon,
  topic,
  nonMobileStatus,
  mobileActions,
  onRemove,
  className,
  removeButtonRef,
}: TopicIndicatorFlashProps) {
  return (
    <div className={clsx(styles.container, className)}>
      <span className={styles.icon}>{icon}</span>
      <span>{topic}</span>
      <span style={{flex: 1}} />
      {nonMobileStatus !== undefined && (
        <div className={clsx(styles.nonMobileOnly, styles.status)}>{nonMobileStatus}</div>
      )}
      {mobileActions !== undefined && <div className={styles.mobileOnly}>{mobileActions}</div>}
      <IconButton
        icon={XIcon}
        variant="invisible"
        size="small"
        aria-label="Remove topic"
        onClick={onRemove}
        className={styles.removeButton}
        ref={removeButtonRef}
      />
    </div>
  )
}
