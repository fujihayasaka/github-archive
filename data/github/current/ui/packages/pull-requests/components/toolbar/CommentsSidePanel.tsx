import {CommentIcon, XIcon} from '@primer/octicons-react'
import {Dialog, Heading, IconButton, Spinner} from '@primer/react'
import {memo, Suspense, useEffect, useCallback, useMemo, useRef, useState} from 'react'
import {CommentsFilter, type CommentsFilterState, filterComments, getDefaultFilterState} from './CommentsFilter'
import {ZeroState} from './ZeroState'
import {ThreadPreview} from './ThreadPreview'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {RelayEnvironmentProvider} from 'react-relay'
import type {Author, CommentingImplementation} from '@github-ui/conversations'
import type {ThreadPreviewsPayload} from '../../page-data/payloads/thread-previews'
import {debounce} from '@github/mini-throttle'
import {announce} from '@github-ui/aria-live'
import type {PageLimits} from '../../page-data/payloads/files'
import {Banner} from '@primer/react/experimental'

interface CommentsSidePanelProps {
  commentBoxConfig: CommentingImplementation['commentBoxConfig']
  toggleSidesheetRef: React.RefObject<HTMLButtonElement>
  onClose: () => void
  pageLimits: PageLimits
  pullRequestId: string
  repositoryId: string
  isOpen: boolean
  tabSize?: number
  threadPreviews: ThreadPreviewsPayload
}

const relayEnvironment = relayEnvironmentWithMissingFieldHandlerForNode()

/**
 *
 * Renders a sidesheet displaying previews of the pull request's threads
 */
export const CommentsSidePanel = memo(function CommentsSidePanel({
  commentBoxConfig,
  onClose,
  isOpen,
  pageLimits,
  pullRequestId,
  repositoryId,
  threadPreviews,
  toggleSidesheetRef,
  tabSize,
}: CommentsSidePanelProps) {
  const [filterState, setFilterState] = useState<CommentsFilterState>(() => getDefaultFilterState())
  const filteredThreadIds = filterComments(threadPreviews, filterState)
  const closeButtonRef = useRef<HTMLButtonElement>(null)

  const hasThreads = threadPreviews.length > 0
  const navigateToThread = useCallback(() => {
    onClose()
  }, [onClose])

  const authorList = useMemo(() => {
    const authors: Author[] = []

    for (const thread of threadPreviews) {
      const firstComment = thread?.firstComment
      if (firstComment?.author && !authors.some(author => author.login === firstComment.author?.login)) {
        // Copilot goes to the top of the filter
        if (firstComment.author.login === 'Copilot') {
          authors.unshift(firstComment.author)
        } else {
          authors.push(firstComment.author)
        }
      }
    }

    return authors
  }, [threadPreviews])

  const threadSummaries = threadPreviews
    .map(thread => {
      if (!thread || !filteredThreadIds.has(thread.threadId)) return null
      return (
        <ThreadPreview
          commentBoxConfig={commentBoxConfig}
          key={thread.threadId}
          tabSize={tabSize}
          thread={thread}
          onNavigateToDiffComment={navigateToThread}
          pullRequestId={pullRequestId}
          repositoryId={repositoryId}
        />
      )
    })
    .filter(Boolean)

  const announceRef = useRef<HTMLDivElement>(null)
  const debouncedAnnounce = useMemo(() => debounce(announce, 300), [])
  useEffect(() => {
    if (!isOpen) return
    const announceText =
      threadSummaries.length > 0
        ? `${threadSummaries.length} ${threadSummaries.length === 1 ? 'comment' : 'comments'}`
        : `No comments found`
    debouncedAnnounce(announceText, {element: announceRef.current as HTMLElement})
  }, [isOpen, debouncedAnnounce, threadSummaries])

  if (!isOpen) return null

  return (
    <Dialog
      aria-label="Comments list"
      initialFocusRef={closeButtonRef}
      position={{narrow: 'fullscreen', regular: 'right', wide: 'right'}}
      returnFocusRef={toggleSidesheetRef}
      onClose={onClose}
      title="Comments"
      renderHeader={() => (
        <Dialog.Header className="p-3">
          <div className="d-flex flex-row flex-justify-between flex-items-center width-full">
            <Heading as="h3" sx={{fontSize: 2, fontWeight: 600}}>
              Comments
            </Heading>
            <IconButton
              ref={closeButtonRef}
              aria-label="Close comments panel"
              icon={XIcon}
              variant="invisible"
              onClick={onClose}
            />
          </div>
          <CommentsFilter
            authorList={authorList}
            className="mt-2 width-full"
            filterState={filterState}
            onFilterStateChange={setFilterState}
          />
        </Dialog.Header>
      )}
    >
      {pageLimits.reviewThreadsLimitExceeded && (
        <Banner
          aria-label="Warning"
          title="Warning"
          variant="warning"
          hideTitle
          description={`Only the first ${pageLimits.reviewThreadsLimit} comments are currently being shown.`}
          className="mb-3"
        />
      )}
      {threadSummaries.length > 0 ? (
        <Suspense fallback={<Spinner />}>
          <RelayEnvironmentProvider environment={relayEnvironment}>
            <div className="d-flex flex-column position-relative width-full gap-3">{threadSummaries}</div>
          </RelayEnvironmentProvider>
        </Suspense>
      ) : (
        <div className="d-flex flex-column position-relative width-full height-full flex-justify-center">
          <ZeroState
            description="Comments will show up here as soon as there are some."
            heading={hasThreads ? 'No comments match the current filter' : 'No comments on changes yet'}
            icon={CommentIcon}
          />
        </div>
      )}
      <div className="sr-only" aria-live="polite" aria-atomic="true" ref={announceRef} />
    </Dialog>
  )
})
