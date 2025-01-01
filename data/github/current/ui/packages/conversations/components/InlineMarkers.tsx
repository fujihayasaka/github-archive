import {Button} from '@primer/react'
import {type RefObject, useCallback, useEffect, useState} from 'react'

import {DialogStateProvider} from '../contexts/DialogStateContext'
import {useInlineCommentDialogModeContext} from '../contexts/InlineCommentDialogModeContext'
import type {
  CommentAuthor,
  CommentingImplementation,
  ConfigureSuggestedChangesImplementation,
  DiffAnnotation,
  ThreadSummary,
} from '../types'
import type {InlineReviewThreadProps} from './InlineReviewThread'
import {InlineReviewThread} from './InlineReviewThread'

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
  isMarkerListOpen: boolean
  onCloseConversationDialog: () => void
  onCloseConversationList: () => void
  onCloseFocusMode: () => void
  enterDialogMode: (shouldFocusStartCommentButton?: boolean) => void
  onThreadSelected: (threadId: string) => void
  onAnnotationSelected: (annotationId: string) => void
  returnFocusRef: RefObject<HTMLElement>
  manuallyUpdateCommentsWithThisThreadId?: string
  startConversationElementJSX?: JSX.Element | null
  selectedThreadId?: string | null
  selectedAnnotationId?: string | null
  threadsConnectionId?: string
  suggestedChangesConfig?: ConfigureSuggestedChangesImplementation
  ghostUser?: CommentAuthor
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
  commentingImplementation,
  conversationListThreads,
  isMarkerListOpen,
  fileAnchor,
  filePath,
  onAnnotationSelected,
  onCloseConversationDialog,
  onCloseConversationList,
  onCloseFocusMode,
  onThreadSelected,
  returnFocusRef,
  selectedAnnotationId,
  startConversationElementJSX,
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
  return (
    // eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions
    <div
      style={{marginLeft: '-20px', marginRight: '-94px', maxWidth: '633px', width: '100%'}}
      onClick={() => {
        if (!isInDialogMode) enableInlineCommentDialogMode()
      }}
    >
      {isInDialogMode && (
        <Button
          variant="default"
          size="small"
          // Using onMouseUp instead of onClick to custom handle onKeyUp events
          onMouseUp={onCloseFocusMode}
          onKeyUp={e => {
            // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
            if (e.key === 'Enter' || e.code === 'Space') onCloseFocusMode()
          }}
          // TODO: convert this to css classname
          style={{
            position: 'absolute',
            left: '-40px',
            top: '-1px',
          }}
        >
          Exit
        </Button>
      )}
      {conversationListThreads.map(thread => (
        <InlineReviewThread
          manuallyUpdateCommentsWithThisThreadId={manuallyUpdateCommentsWithThisThreadId}
          enterDialogMode={enterDialogMode}
          key={`review-thread-${thread.id}`}
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
      ))}
      {startConversationElementJSX}
    </div>
  )
}
