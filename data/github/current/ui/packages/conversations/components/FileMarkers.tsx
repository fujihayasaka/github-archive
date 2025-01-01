import {clsx} from 'clsx'
import {useRef} from 'react'

import {useMarkerNavigation} from '../hooks/use-marker-navigation'
import type {CommentAuthor, CommentingImplementation, Thread} from '../types'
import {FileReviewThread} from './FileReviewThread'
import styles from './InlineMarkers.module.css'
import type {InlineReviewThreadProps} from './InlineReviewThread'

export interface FileMarkersProps
  extends Pick<InlineReviewThreadProps, 'batchPending' | 'repositoryId' | 'subjectId' | 'subject' | 'viewerData'> {
  commentingImplementation: CommentingImplementation
  conversationListThreads: Thread[]
  filePath: string
  manuallyUpdateCommentsWithThisThreadId?: string
  selectedThreadId?: string | null
  ghostUser?: CommentAuthor
}

export function FileMarkers({
  batchPending,
  commentingImplementation,
  conversationListThreads,
  filePath,
  selectedThreadId,
  manuallyUpdateCommentsWithThisThreadId,
  ghostUser,
  ...rest
}: FileMarkersProps) {
  // Create a ref for the markers container
  const markersContainerRef = useRef<HTMLDivElement>(null)

  const selectedMarkerId = selectedThreadId
    ? selectedThreadId
    : conversationListThreads.length > 0
      ? conversationListThreads[0]?.id
      : null

  // Use our marker navigation hook
  useMarkerNavigation({
    containerRef: markersContainerRef,
    markers: conversationListThreads,
    disabled: false,
    focusInStrategy: 'closest',
    selectedMarkerId,
  })
  return (
    <div className={'d-flex pt-1 pl-1'}>
      <div className={styles.fileMarkersWrapper} ref={markersContainerRef}>
        {conversationListThreads.map((thread, i) => (
          <div
            key={`review-thread-${thread.id}`}
            className={clsx(
              'mt-1 border rounded-2 color-border-default color-shadow-small',
              i === conversationListThreads.length - 1 ? 'mb-1' : 'mb-2',
            )}
            data-first-marker={i === 0}
            data-marker-id={`${thread.id}`} // Add data-marker-id attribute for keyboard navigation
            // eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex
            tabIndex={0} // Make the marker focusable
          >
            <FileReviewThread
              key={thread.id}
              batchPending={batchPending}
              commentingImplementation={commentingImplementation}
              repositoryId={rest.repositoryId}
              subjectId={rest.subjectId}
              subject={rest.subject}
              viewerData={rest.viewerData}
              filePath={filePath}
              thread={thread}
              ghostUser={ghostUser}
            />
          </div>
        ))}
      </div>
    </div>
  )
}
