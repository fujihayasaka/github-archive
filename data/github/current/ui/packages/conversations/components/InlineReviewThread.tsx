import type {LineRange} from '@github-ui/diff-lines'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {useAnalytics} from '@github-ui/use-analytics'
import {CheckCircleFillIcon, CheckCircleIcon} from '@primer/octicons-react'
import {Box, IconButton, Label, Spinner, Text} from '@primer/react'
import {Tooltip} from '@primer/react/next'
import type {PropsWithChildren} from 'react'
import {Suspense, useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {useInlineCommentDialogModeContext} from '../contexts/InlineCommentDialogModeContext'
import type {CommentAuthor, ConfigureSuggestedChangesImplementation, Thread, ThreadSummary} from '../types'
import {hideInteractiveElements, showInteractiveElements} from '../util/hide-show-interactive-elements'
import type {ReviewThreadProps} from './ReviewThread'
import {ReviewThread} from './ReviewThread'

function Emphasis({children}: PropsWithChildren) {
  return <Text sx={{fontWeight: 500, color: 'fg.default'}}>{children}</Text>
}

function ThreadBanner({thread}: {thread?: ThreadSummary}) {
  if (typeof thread === 'undefined') return null
  if (!thread?.diffSide || !thread.line) return null

  if (!thread.startLine || !thread.startDiffSide) {
    return SingleLineThreadBanner({thread})
  } else {
    return MultineLineThreadBanner({thread})
  }
}

function SingleLineThreadBanner({thread}: {thread: ThreadSummary}) {
  const startSideString = thread.startDiffSide === 'LEFT' ? 'L' : 'R'
  return (
    <Text sx={{color: 'fg.muted', pl: 2}}>
      Comment on line{' '}
      <Emphasis>
        {startSideString}
        {thread.line}
      </Emphasis>
    </Text>
  )
}

function MultineLineThreadBanner({thread}: {thread: ThreadSummary}) {
  const startSideString = thread.startDiffSide === 'LEFT' ? 'L' : 'R'
  const endSideString = thread.diffSide === 'LEFT' ? 'L' : 'R'
  return (
    <Text sx={{color: 'fg.muted', pl: 2}}>
      Comment on lines{' '}
      <Emphasis>
        {startSideString}
        {thread.startLine}
      </Emphasis>{' '}
      to{' '}
      <Emphasis>
        {endSideString}
        {thread.line}
      </Emphasis>
    </Text>
  )
}

export interface InlineReviewThreadProps
  extends Pick<
    ReviewThreadProps,
    | 'batchingEnabled'
    | 'batchPending'
    | 'commentingImplementation'
    | 'repositoryId'
    | 'subjectId'
    | 'subject'
    | 'viewerData'
  > {
  threadId: string
  isOutdated: boolean
  fileAnchor?: string
  filePath: string
  onThreadSelected: (threadId: string) => void
  enterDialogMode: (shouldFocusStartCommentButton?: boolean) => void
  threads: ThreadSummary[]
  threadsConnectionId?: string
  ghostUser?: CommentAuthor
  manuallyUpdateCommentsWithThisThreadId?: string
  suggestedChangesConfig?: ConfigureSuggestedChangesImplementation
}

/**
 * The InlineReviewThread opens from the ActionBar when the user selects a conversation.
 */
export function InlineReviewThread({
  commentingImplementation,
  fileAnchor,
  filePath,
  threadId,
  isOutdated,
  threads,
  threadsConnectionId,
  enterDialogMode,
  ghostUser,
  manuallyUpdateCommentsWithThisThreadId,
  suggestedChangesConfig,
  ...rest
}: InlineReviewThreadProps) {
  const [thread, setThread] = useState<Thread | undefined>(undefined)
  const {fetchThread} = commentingImplementation
  const reviewThreadRef = useRef<HTMLDivElement>(null)
  const {isInDialogMode} = useInlineCommentDialogModeContext()

  const fetchThreadData = useCallback(
    async (threadIdentifier: string, isRefetch: boolean = true) => {
      // Adding temporary concept of isRefetch param to the thread fetch until threads are batched in a future issue.
      const fetchedThread = await fetchThread(threadIdentifier, isRefetch)
      setThread(fetchedThread)
    },
    [fetchThread],
  )

  useEffect(() => {
    fetchThreadData(threadId, false)
  }, [fetchThreadData, manuallyUpdateCommentsWithThisThreadId, threadId])

  useEffect(() => {
    if (!isInDialogMode || (!isInDialogMode && thread)) {
      hideInteractiveElements(reviewThreadRef.current)
    } else {
      showInteractiveElements(reviewThreadRef.current)
    }
  }, [isInDialogMode, thread])

  useEffect(() => {
    if (!thread) fetchThreadData(threadId, false)
  }, [threadId, thread, fetchThread, fetchThreadData])

  const config = useMemo(() => {
    if (
      fileAnchor &&
      thread &&
      thread.subject?.startDiffSide &&
      thread.subject?.endDiffSide &&
      thread.subject?.startLine &&
      thread.subject?.endLine &&
      suggestedChangesConfig?.configureSuggestedChangesFromLineRange
    ) {
      const startLine = thread.subject?.startLine ?? thread?.subject?.endLine
      const startDiffSide = thread.subject?.startDiffSide ?? thread?.subject?.endDiffSide

      const threadRowRange: LineRange = {
        diffAnchor: fileAnchor,
        endLineNumber: thread?.subject?.endLine,
        endOrientation: thread.subject?.endDiffSide === 'LEFT' ? 'left' : 'right',
        startLineNumber: startLine,
        firstSelectedLineNumber: startLine,
        firstSelectedOrientation: startDiffSide === 'LEFT' ? 'left' : 'right',
        startOrientation: startDiffSide === 'LEFT' ? 'left' : 'right',
      }
      return suggestedChangesConfig?.configureSuggestedChangesFromLineRange(threadRowRange)
    }

    return undefined
  }, [fileAnchor, thread, suggestedChangesConfig])

  const {sendAnalyticsEvent} = useAnalytics()
  const {resolveThread, unresolveThread, resolvingEnabled} = commentingImplementation
  const threadSummary = threads.find(current => current.id === threadId)
  const {addToast} = useToastContext()

  const handleResolveThread = () => {
    if (!thread) return

    resolveThread({
      thread,
      onCompleted: () => fetchThreadData(thread.id),
      onError: () => {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: 'Failed to resolve thread',
        })
      },
    })

    sendAnalyticsEvent('comments.resolve_thread', 'RESOLVE_CONVERSATION_BUTTON')
  }

  const handleUnresolveThread = () => {
    if (!thread) return

    unresolveThread({
      thread,
      onCompleted: () => fetchThreadData(thread.id),
      onError: () => {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: 'Failed to unresolve thread',
        })
      },
    })

    sendAnalyticsEvent('comments.unresolve_thread', 'RESOLVE_CONVERSATION_BUTTON')
  }

  if (!thread) return null

  const hasComments = thread.commentsData.comments.length > 0

  if (!hasComments) return null

  const isThreadResolved = !!thread.isResolved
  const resolvedTokenText = 'Resolved'
  const commentsConnectionId = threadSummary?.commentsConnectionId

  return (
    <Box sx={{mb: 1, mt: 1}} className="bgColor-default rounded-2" ref={reviewThreadRef}>
      <Box
        sx={{
          display: 'flex',
          flexDirection: 'row',
          width: '100%',
          alignItems: 'center',
          borderBottom: '1px solid',
          borderColor: 'border.muted',
        }}
      >
        <ThreadBanner thread={threadSummary} />
        <Box
          sx={{
            display: 'flex',
            flexDirection: 'row',
            gap: 1,
            alignItems: 'center',
            justifyContent: 'right',
            flexGrow: 1,
          }}
        >
          {isThreadResolved && (
            <Label variant="done" size="large">
              {resolvedTokenText}
            </Label>
          )}

          {resolvingEnabled && (
            <Tooltip
              text={isThreadResolved ? 'Unresolve conversation' : 'Resolve conversation'}
              type="label"
              direction="w"
              id="resolve-conversation"
            >
              <IconButton
                aria-labelledby="resolve-conversation"
                icon={isThreadResolved ? CheckCircleFillIcon : CheckCircleIcon}
                // need to be specific in order to override default IconButton color
                sx={{color: isThreadResolved ? 'var(--fgColor-done, var(--color-done-fg)) !important' : undefined}}
                variant="invisible"
                onClick={isThreadResolved ? handleUnresolveThread : handleResolveThread}
              />
            </Tooltip>
          )}
        </Box>
      </Box>
      <Suspense
        fallback={
          <Box
            sx={{
              height: '90px',
              alignItems: 'center',
              display: 'flex',
              flexDirection: 'column',
              justifyContent: 'center',
              color: 'fg.muted',
              fontSize: 0,
            }}
          >
            <Spinner />
            <p>Loading comments</p>
          </Box>
        }
      >
        <ReviewThread
          enterDialogMode={enterDialogMode}
          commentingImplementation={commentingImplementation}
          commentsConnectionId={commentsConnectionId}
          filePath={filePath}
          onRefreshThread={fetchThreadData}
          thread={thread}
          threadsConnectionId={threadsConnectionId}
          suggestedChangesConfig={config}
          shouldLimitHeight={false}
          {...rest}
          ghostUser={ghostUser}
        />
      </Suspense>
    </Box>
  )
}
