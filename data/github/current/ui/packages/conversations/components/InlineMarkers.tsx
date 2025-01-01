import {getLineBackgroundColor} from '@github-ui/diff-lines/line-helpers'
import type {DiffLineType} from '@github-ui/diffs/types'
import {UndoIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {clsx} from 'clsx'
import {type RefObject, useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {DialogStateProvider} from '../contexts/DialogStateContext'
import {useInlineCommentDialogModeContext} from '../contexts/InlineCommentDialogModeContext'
import type {GenericMarkerNavEl} from '../helpers/marker-navigator'
import {useMarkerNavigation} from '../hooks/use-marker-navigation'
import type {
  CommentAuthor,
  CommentingImplementation,
  ConfigureSuggestedChangesImplementation,
  DiffAnnotation,
  ThreadSummary,
} from '../types'
import {DiffAnnotationLevels} from '../types'
import {InlineAnnotation} from './InlineAnnotation'
import styles from './InlineMarkers.module.css'
import type {InlineReviewThreadProps} from './InlineReviewThread'
import {InlineReviewThread} from './InlineReviewThread'

// Define annotation levels priority for sorting
const annotationLevelPriority = {
  [DiffAnnotationLevels.Failure]: 0,
  [DiffAnnotationLevels.Warning]: 1,
  [DiffAnnotationLevels.Notice]: 2,
}

export interface InlineMarkersProps
  extends Pick<
    InlineReviewThreadProps,
    'batchingEnabled' | 'batchPending' | 'repositoryId' | 'subjectId' | 'subject' | 'viewerData'
  > {
  annotations: DiffAnnotation[]
  commentingImplementation: CommentingImplementation
  conversationListThreads: ThreadSummary[]
  fileAnchor?: string
  filePath: string
  gutterSizeOffset: string
  inlineMarkersRef: RefObject<HTMLDivElement>
  isMarkerListOpen: boolean
  isRowSelected: boolean
  lineType: DiffLineType
  onCloseConversationList: () => void
  onCloseFocusMode: () => void
  enterDialogMode: (shouldFocusStartCommentButton?: boolean) => void
  onThreadSelected: (threadId: string) => void
  onAnnotationSelected: (annotationId: string) => void
  returnFocusRef: RefObject<HTMLElement>
  manuallyUpdateCommentsWithThisThreadId?: string
  selectedThreadId?: string | null
  selectedAnnotationId?: string | null
  threadsConnectionId?: string
  suggestedChangesConfig?: ConfigureSuggestedChangesImplementation
  ghostUser?: CommentAuthor
  children?: React.ReactNode
}

export function InlineMarkers(props: InlineMarkersProps) {
  return (
    <DialogStateProvider>
      <InlineMarkersInternal {...props} />
    </DialogStateProvider>
  )
}

function InlineMarkersInternal({
  annotations,
  children,
  commentingImplementation,
  conversationListThreads,
  inlineMarkersRef,
  isMarkerListOpen,
  isRowSelected,
  fileAnchor,
  filePath,
  gutterSizeOffset,
  lineType,
  onAnnotationSelected,
  onCloseConversationList,
  onCloseFocusMode,
  onThreadSelected,
  returnFocusRef,
  selectedAnnotationId,
  selectedThreadId,
  threadsConnectionId,
  suggestedChangesConfig,
  manuallyUpdateCommentsWithThisThreadId,
  ghostUser,
  enterDialogMode,
  ...rest
}: InlineMarkersProps) {
  //after a user adds a comment, we want to re-render the inline comment component to fetch that comment's data from
  //the server and update the UI. This is a hacky way to do that, but it works. If we swap to a better state management
  //system down the line, this can be torn out in favor of that.
  const fetchThreadData = useCallback(
    async (threadIdentifier: string) => {
      const fetchedThread = await commentingImplementation.fetchThread(threadIdentifier, false)
      //the only relevant part of the fetched thread is the ID, which is consistent, so I do this conversion
      //to avoid wasted time
      if (fetchedThread) conversationListThreads.push(fetchedThread as unknown as ThreadSummary)
      setTheRerenderState({})
    },
    [commentingImplementation, conversationListThreads],
  )

  const [_, setTheRerenderState] = useState({})
  useEffect(() => {
    if (
      conversationListThreads.length === 0 &&
      manuallyUpdateCommentsWithThisThreadId &&
      manuallyUpdateCommentsWithThisThreadId !== ''
    ) {
      fetchThreadData(manuallyUpdateCommentsWithThisThreadId)
    }
  }, [
    commentingImplementation,
    conversationListThreads.length,
    fetchThreadData,
    manuallyUpdateCommentsWithThisThreadId,
  ])
  const {isInDialogMode, enableInlineCommentDialogMode} = useInlineCommentDialogModeContext()

  // Create a ref for the markers container
  const markersContainerRef = useRef<HTMLDivElement>(null)

  // Sort annotations by level: Failure > Warning > Notice
  const sortedAnnotations = useMemo(() => {
    return [...annotations].sort((a, b) => {
      return annotationLevelPriority[a.annotationLevel] - annotationLevelPriority[b.annotationLevel]
    })
  }, [annotations])

  const markers: Array<ThreadSummary | GenericMarkerNavEl> = useMemo(() => {
    if (children) {
      return [...conversationListThreads, {id: 'new-comment'} as GenericMarkerNavEl, ...sortedAnnotations]
    }

    return [...conversationListThreads, ...sortedAnnotations]
  }, [children, conversationListThreads, sortedAnnotations])

  // Use our marker navigation hook
  useMarkerNavigation({
    containerRef: markersContainerRef,
    markers,
    disabled: !isInDialogMode, // Only enable marker navigation when in dialog mode
    selectedMarkerId: selectedThreadId,
  })

  return (
    <div
      className={clsx('d-flex pt-1', isInDialogMode ? styles.markersDialogActive : '')}
      style={
        isInDialogMode
          ? {
              marginRight: `-${gutterSizeOffset}`,
              backgroundColor: getLineBackgroundColor(lineType, true, isRowSelected),
            }
          : {marginRight: `-${gutterSizeOffset}`}
      }
      onFocus={() => {
        if (!isInDialogMode) {
          enableInlineCommentDialogMode()
        }
      }}
      data-inline-markers
      ref={inlineMarkersRef}
    >
      <div className={styles.markersWrapper} ref={markersContainerRef}>
        {conversationListThreads.map((thread, i) => (
          <div
            key={`review-thread-${thread.id}`}
            className={clsx(
              'mt-1 border rounded-2 color-border-default color-shadow-small',
              i === markers.length - 1 ? 'mb-1' : 'mb-2',
            )}
            data-first-marker={i === 0}
            data-marker-id={`${thread.id}`} // Add data-marker-id attribute for keyboard navigation
            // eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex
            tabIndex={isInDialogMode ? 0 : -1} // Make the marker focusable
          >
            <InlineReviewThread
              threadPositionNumber={i + 1}
              manuallyUpdateCommentsWithThisThreadId={manuallyUpdateCommentsWithThisThreadId}
              enterDialogMode={enterDialogMode}
              isFirstThread={i === 0}
              commentingImplementation={commentingImplementation}
              filePath={filePath}
              fileAnchor={fileAnchor}
              threadId={thread.id}
              isOutdated={thread.isOutdated}
              threads={conversationListThreads}
              threadsConnectionId={threadsConnectionId}
              onThreadSelected={onThreadSelected}
              suggestedChangesConfig={suggestedChangesConfig}
              ghostUser={ghostUser}
              {...rest}
            />
          </div>
        ))}
        {children}
        {sortedAnnotations.map((annotation, i) => {
          const isFirstMarker = i === 0 && annotation === markers[0]
          return (
            <InlineAnnotation
              key={`annotation-${annotation.id}`}
              annotation={annotation}
              commentingImplementation={commentingImplementation}
              isFirstMarker={isFirstMarker}
            />
          )
        })}
      </div>
      {isInDialogMode && (
        <IconButton
          icon={UndoIcon}
          className={clsx(
            styles.closeMarkersDialogButton,
            'ml-2 position-relative',
            conversationListThreads.length === 0 ? 'mt-2' : 'mt-1',
          )}
          aria-label="Return to code"
          data-exit-dialog-mode-button={'true'}
          variant="default"
          size="small"
          // Using onMouseUp instead of onClick to custom handle onKeyDown events
          onMouseUp={onCloseFocusMode}
          onKeyDown={e => {
            // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
            if (e.key === 'Enter' || e.code === 'Space') onCloseFocusMode()
          }}
        />
      )}
    </div>
  )
}
