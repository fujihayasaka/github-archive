import {CommentIcon, XIcon} from '@primer/octicons-react'
import {Heading, IconButton, Overlay, Spinner} from '@primer/react'
import {memo, Suspense, useCallback, useRef, useState} from 'react'

import {CommentsFilter, type CommentsFilterState, filterComments, getDefaultFilterState} from './CommentsFilter'
import {ZeroState} from './ZeroState'
import {ThreadPreview} from './ThreadPreview'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {RelayEnvironmentProvider} from 'react-relay'
import type {ThreadPreviewsPayload} from '../page-data/payloads/thread-previews'

interface CommentsSidePanelProps {
  toggleSidesheetRef: React.RefObject<HTMLButtonElement>
  onClose: () => void
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
  onClose,
  isOpen,
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
    // TODO: Navigate to the thread in the Rails Diff
    onClose()
  }, [onClose])

  if (!isOpen) return null

  const threadSummaries = threadPreviews
    .map(thread => {
      if (!thread || !filteredThreadIds.has(thread.id)) return null
      return (
        <ThreadPreview
          key={thread.id}
          tabSize={tabSize}
          thread={thread}
          onNavigateToDiffThread={navigateToThread}
          pullRequestId={pullRequestId}
          repositoryId={repositoryId}
        />
      )
    })
    .filter(Boolean)

  return (
    <Overlay
      anchorSide="inside-left"
      aria-label="Threads"
      className="p-3 pt-0 rounded-right-0 overflow-y-auto"
      initialFocusRef={closeButtonRef}
      position="fixed"
      returnFocusRef={toggleSidesheetRef}
      right={0}
      role="complementary"
      top={0}
      width="xlarge"
      sx={{
        height: '100vh',
        maxHeight: '100vh',
      }}
      onClickOutside={onClose}
      onEscape={onClose}
    >
      <div className="d-flex flex-column flex-items-center height-full">
        <div className="position-sticky width-full top-0 mx-n3 py-3" style={{zIndex: 15}}>
          <div className="d-flex flex-row flex-justify-between flex-items-center width-full">
            <Heading as="h3" sx={{fontSize: 2, fontWeight: 600}}>
              Threads
            </Heading>
            {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
            <IconButton
              ref={closeButtonRef}
              aria-label="Close comments panel"
              icon={XIcon}
              unsafeDisableTooltip
              variant="invisible"
              onClick={onClose}
            />
          </div>
          <CommentsFilter className="mt-2 width-full" filterState={filterState} onFilterStateChange={setFilterState} />
        </div>
        {threadSummaries.length > 0 ? (
          <Suspense fallback={<Spinner />}>
            <RelayEnvironmentProvider environment={relayEnvironment}>
              <div className="d-flex flex-column position-relative width-full pb-5 gap-3">{threadSummaries}</div>
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
      </div>
    </Overlay>
  )
})
