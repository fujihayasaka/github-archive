import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import safeStorage from '@github-ui/safe-storage'
import {useAnalytics} from '@github-ui/use-analytics'
import {CheckCircleFillIcon, CheckCircleIcon, ChevronDownIcon, ChevronRightIcon, StopIcon} from '@primer/octicons-react'
import {Box, Flash, IconButton, Label, Spinner, Tooltip} from '@primer/react'
import {Suspense, useEffect, useRef, useState} from 'react'

import {CommentErrorFallback} from '../CommentErrorFallback'
import type {CommentAuthor, Thread} from '../conversations'
import {ReviewThread, type ReviewThreadProps} from './ReviewThread'

export interface FileReviewThreadProps
  extends Pick<
    ReviewThreadProps,
    'batchPending' | 'commentingImplementation' | 'repositoryId' | 'subjectId' | 'subject' | 'viewerData'
  > {
  fileAnchor?: string
  filePath: string
  thread: Thread
  ghostUser?: CommentAuthor
  manuallyUpdateCommentsWithThisThreadId?: string
  isFirstThread?: boolean
}

export function FileReviewThread({
  batchPending,
  commentingImplementation,
  fileAnchor,
  filePath,
  thread,
  isFirstThread,
  ghostUser,
  manuallyUpdateCommentsWithThisThreadId,
  ...rest
}: FileReviewThreadProps) {
  const {resolveThread, unresolveThread, resolvingEnabled} = commentingImplementation
  const reviewThreadRef = useRef<HTMLDivElement>(null)
  const safeLocalStorage = safeStorage('localStorage')
  const isResolved = thread?.isResolved

  const [errorMessage, setErrorMessage] = useState('')
  const [isCollapsed, setIsCollapsed] = useState<boolean>(isResolved ?? false)

  useEffect(() => {
    const storedState = localStorage.getItem(`reviewThreadIsCollapsed_${thread.id}`)
    if (storedState !== null) {
      setIsCollapsed(JSON.parse(storedState))
    } else if (isResolved) {
      setIsCollapsed(true)
    }
  }, [isResolved, thread.id])

  const handleToggleCollapsed = () => {
    window.requestAnimationFrame(() => {
      safeLocalStorage.setItem(`reviewThreadIsCollapsed_${thread.id}`, JSON.stringify(!isCollapsed))
    })
    setIsCollapsed((prevIsCollapsed: boolean) => !prevIsCollapsed)
  }

  const {sendAnalyticsEvent} = useAnalytics()

  const handleResolveThread = () => {
    if (!thread) return

    resolveThread({
      threadId: thread.id,
      onCompleted: () => {
        setIsCollapsed(true)
        safeLocalStorage.removeItem(`reviewThreadIsCollapsed_${thread.id}`)
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
        setIsCollapsed(false)
        safeLocalStorage.removeItem(`reviewThreadIsCollapsed_${thread.id}`)
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
              <StopIcon className="mr-2" />
              {errorMessage}
            </Flash>
          )}
          {!isCollapsed && (
            <ReviewThread
              batchPending={batchPending}
              batchingEnabled={commentingImplementation.batchingEnabled}
              commentingImplementation={commentingImplementation}
              filePath={filePath}
              isInlineComment={false}
              onRefreshThread={() => {}}
              thread={thread}
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
