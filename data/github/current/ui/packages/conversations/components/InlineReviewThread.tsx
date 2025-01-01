import type {LineRange} from '@github-ui/diff-lines'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import safeStorage from '@github-ui/safe-storage'
import {useAnalytics} from '@github-ui/use-analytics'
import {CheckCircleFillIcon, CheckCircleIcon, ChevronDownIcon, ChevronRightIcon, StopIcon} from '@primer/octicons-react'
import {Box, Flash, IconButton, Label, Spinner, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {Tooltip} from '@primer/react/next'
import type {PropsWithChildren} from 'react'
import {Suspense, useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {CommentErrorFallback} from '../CommentErrorFallback'
import {useInlineCommentDialogModeInteractiveElements} from '../hooks/use-inline-comment-dialog-mode-interactive-elements'
import type {CommentAuthor, ConfigureSuggestedChangesImplementation, Thread, ThreadSummary} from '../types'
import styles from './InlineReviewThread.module.css'
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
  const diffSideLetter = thread.diffSide === 'LEFT' ? 'L' : 'R'
  return (
    <h2 className={styles.inlineReviewThreadHeading}>
      Comment on line{' '}
      <Emphasis>
        {diffSideLetter}
        {thread.line}
      </Emphasis>
    </h2>
  )
}

function MultineLineThreadBanner({thread}: {thread: ThreadSummary}) {
  const startSideString = thread.startDiffSide === 'LEFT' ? 'L' : 'R'
  const endSideString = thread.diffSide === 'LEFT' ? 'L' : 'R'
  return (
    <h2 className={styles.inlineReviewThreadHeading}>
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
    </h2>
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
  isFirstThread?: boolean
  threadPositionNumber?: number
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
  threadPositionNumber,
  isOutdated,
  threads,
  threadsConnectionId,
  isFirstThread,
  enterDialogMode,
  ghostUser,
  manuallyUpdateCommentsWithThisThreadId,
  suggestedChangesConfig,
  ...rest
}: InlineReviewThreadProps) {
  const [thread, setThread] = useState<Thread | undefined>(undefined)
  const {fetchThread, shouldRefetchThread} = commentingImplementation
  const reviewThreadRef = useRef<HTMLDivElement>(null)
  const safeLocalStorage = safeStorage('localStorage')
  const isResolved = thread?.isResolved

  const [errorMessage, setErrorMessage] = useState('')
  const [isCollapsed, setIsCollapsed] = useState<boolean>(isResolved ?? false)

  useEffect(() => {
    const storedState = localStorage.getItem(`reviewThreadIsCollapsed_${threadId}`)
    if (storedState !== null) {
      setIsCollapsed(JSON.parse(storedState))
    } else if (isResolved) {
      setIsCollapsed(true)
    }
  }, [isResolved, threadId])

  const handleToggleCollapsed = () => {
    window.requestAnimationFrame(() => {
      safeLocalStorage.setItem(`reviewThreadIsCollapsed_${threadId}`, JSON.stringify(!isCollapsed))
    })
    setIsCollapsed((prevIsCollapsed: boolean) => !prevIsCollapsed)
  }

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

  useInlineCommentDialogModeInteractiveElements({
    commentSubjectType: commentingImplementation.commentSubjectType,
    markerRef: reviewThreadRef,
  })

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

  useEffect(() => {
    if (thread && shouldRefetchThread?.(thread)) {
      fetchThreadData(threadId, true)
    }
  }, [fetchThreadData, shouldRefetchThread, thread, threadId, threads])

  const {sendAnalyticsEvent} = useAnalytics()
  const {resolveThread, unresolveThread, resolvingEnabled} = commentingImplementation
  const threadSummary = threads.find(current => current.id === threadId)

  const handleResolveThread = () => {
    if (!thread) return

    resolveThread({
      threadId: thread.id,
      onCompleted: () => {
        // If we don't have a condition to refetch using the effect, refetch after resolving
        if (!shouldRefetchThread) {
          fetchThreadData(thread.id)
        }
        setIsCollapsed(true)
        safeLocalStorage.removeItem(`reviewThreadIsCollapsed_${threadId}`)
      },
      onError: () => {
        setErrorMessage('Failed to resolve thread')
      },
    })

    sendAnalyticsEvent('comments.resolve_thread', 'RESOLVE_CONVERSATION_BUTTON')
  }

  const handleUnresolveThread = () => {
    if (!thread) return

    unresolveThread({
      threadId: thread.id,
      onCompleted: () => {
        // If we don't have a condition to refetch using the effect, refetch after resolving
        if (!shouldRefetchThread) {
          fetchThreadData(thread.id)
        }
        setIsCollapsed(false)
        safeLocalStorage.removeItem(`reviewThreadIsCollapsed_${threadId}`)
      },
      onError: () => {
        setErrorMessage('Failed to unresolve thread')
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
  const isResolveable =
    resolvingEnabled && thread.commentsData.comments.some(comment => comment.state?.toUpperCase() !== 'PENDING')

  return (
    <ErrorBoundary fallback={<CommentErrorFallback />}>
      <div className="rounded-2 bgColor-default" ref={reviewThreadRef}>
        <Box
          sx={{
            display: 'flex',
            flexDirection: 'row',
            width: '100%',
            alignItems: 'center',
            borderBottom: '1px solid',
            borderColor: 'border.muted',
          }}
          className="px-1"
        >
          <IconButton
            aria-label={isCollapsed ? 'Expand comment' : 'Collapse comment'}
            icon={isCollapsed ? ChevronRightIcon : ChevronDownIcon}
            size="small"
            variant="invisible"
            onClick={handleToggleCollapsed}
            data-is-first-collapse-button={isFirstThread}
          />
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
            {isThreadResolved && <Label variant="secondary">{resolvedTokenText}</Label>}

            {isResolveable && (
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
          {errorMessage && (
            <Flash variant="danger" className="m-2">
              <Octicon icon={StopIcon} className="mr-2" />
              {errorMessage}
            </Flash>
          )}
          {!isCollapsed && (
            <ReviewThread
              enterDialogMode={enterDialogMode}
              commentingImplementation={commentingImplementation}
              commentsConnectionId={commentsConnectionId}
              filePath={filePath}
              isInlineComment
              onRefreshThread={fetchThreadData}
              thread={thread}
              threadPositionNumber={threadPositionNumber}
              threadsConnectionId={threadsConnectionId}
              suggestedChangesConfig={config}
              shouldLimitHeight={false}
              {...rest}
              ghostUser={ghostUser}
            />
          )}
        </Suspense>
      </div>
    </ErrorBoundary>
  )
}
