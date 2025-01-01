import CopilotBadge from '@github-ui/copilot-chat/components/CopilotBadge'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Button, Spinner} from '@primer/react'
import {Banner, type ButtonBaseProps} from '@primer/react/experimental'
import {Tooltip} from '@primer/react/next'
import {clsx} from 'clsx'
import {memo, useCallback} from 'react'

import {useFilesContext} from '../../contexts/FilesContext'
import {useGenerateFix} from '../../hooks/use-generate-fix'
import {useLocalSuggestionState} from '../../hooks/use-local-suggestion-state'
import {useTaskApplicableData} from '../../hooks/use-task-applicable-data'
import {AnalyticsContext} from '../../telemetry/AnalyticsContext'
import type {IGeneratedFixMetadata, SendAnalyticsEventFunction} from '../../telemetry/interfaces'
import {useAnalytics} from '../../telemetry/use-analytics'
import {mapPatchToDiffLines} from '../../utilities/diff-helpers'
import type {
  DisplayTaskData,
  FocusedGenerativeTaskData,
  WorkspaceEditorRoutePayload,
} from '../../utilities/workspace-editor-types'
import {ApiClientProvider} from '../ApiClientProvider'
import {Diff} from '../Diff'
import {RightSidePanelContent} from '../RightSidePanelComponents'
import {SuggestionFooter} from '../suggestions/SuggestionFooter'
import styles from './GenerateFix.module.css'
import {PullThread, ThreadComment} from './PullRequestThread'
import {SkeletonDiffBlock} from './SkeletonDiffBlock'

export const GENERATE_A_FIX_FLAG = 'hadron_comment_fix_generation'

function ApplyButton({
  applyTooltip,
  isAppliable,
  isApplied,
  onApply,
  variant,
  size,
  disabled,
}: {
  applyTooltip: string
  isAppliable: boolean
  isApplied: boolean
  onApply: () => void
  variant?: ButtonBaseProps['variant']
  size?: ButtonBaseProps['size']
  disabled?: boolean
}) {
  const isButtonDisabled = disabled || !isAppliable || isApplied
  const apply = () => !isButtonDisabled && onApply()
  return (
    <Tooltip hidden={isAppliable} text={applyTooltip} direction="nw">
      <Button
        aria-disabled={isButtonDisabled}
        inactive={isButtonDisabled}
        variant={variant}
        size={size}
        onClick={apply}
      >
        {isApplied ? 'Applied' : 'Apply'}
      </Button>
    </Tooltip>
  )
}

function CopilotComment({comment}: {comment: string}) {
  return (
    <ThreadComment
      actorAvatar={<CopilotBadge />}
      actorLinkable={false}
      comment={{
        id: 0,
        author: {avatarUrl: '', displayLogin: 'Copilot'},
        body: comment,
      }}
    />
  )
}

export type GenerateFixInnerProps = {
  commentsVersion: string
  focusedGenerativeTask: FocusedGenerativeTaskData
  suggestionRequestId: string
  suggestionsForPagination: DisplayTaskData[]
}

export type GenerateFixProps = Pick<GenerateFixInnerProps, 'suggestionsForPagination' | 'focusedGenerativeTask'>

export const GenerateFix = memo(function GenerateFix({
  focusedGenerativeTask,
  suggestionsForPagination,
}: GenerateFixProps) {
  const allComments = [focusedGenerativeTask.comment, ...focusedGenerativeTask.replies]
  const commentsVersion = Math.max(...allComments.map(reply => new Date(reply.updatedAt).getTime())).toString()
  const suggestionRequestId = [
    focusedGenerativeTask.type,
    focusedGenerativeTask.sourceId,
    focusedGenerativeTask.comment.commitOid,
    commentsVersion,
  ].join('-')

  const metadata = useCallback(
    (): IGeneratedFixMetadata => ({
      comment_version: commentsVersion,
      suggestion_request_id: suggestionRequestId,
      comment_id: focusedGenerativeTask.comment.id,
      commit_oid: focusedGenerativeTask.comment.commitOid,
    }),
    [commentsVersion, suggestionRequestId, focusedGenerativeTask],
  )

  const onStart = useCallback((sendEvent: SendAnalyticsEventFunction) => {
    sendEvent('generated-fix.opened')
  }, [])

  const isGenerateFixEnabled = useFeatureFlag(GENERATE_A_FIX_FLAG)
  const waitingForTask = !focusedGenerativeTask
  const showCommentOnly = focusedGenerativeTask && !isGenerateFixEnabled
  const showCommentWithFix = focusedGenerativeTask && isGenerateFixEnabled

  return (
    <AnalyticsContext name="generated_fix" metadata={metadata} onStart={onStart}>
      <ApiClientProvider>
        {waitingForTask && (
          <div style={{textAlign: 'center'}}>
            <Spinner />
          </div>
        )}
        {!waitingForTask && showCommentOnly && (
          <Layout>
            <PullThread
              comments={[focusedGenerativeTask.comment, ...focusedGenerativeTask.replies]}
              isCondensed={false}
            />
          </Layout>
        )}
        {!waitingForTask && showCommentWithFix && (
          <GenerateFixInner
            focusedGenerativeTask={focusedGenerativeTask}
            commentsVersion={commentsVersion}
            suggestionsForPagination={suggestionsForPagination}
            suggestionRequestId={suggestionRequestId}
          />
        )}
      </ApiClientProvider>
    </AnalyticsContext>
  )
})

function Layout({children, footer}: {children: React.ReactNode; footer?: React.ReactNode}) {
  return (
    <ErrorBoundary>
      <RightSidePanelContent>
        <div className="d-flex flex-column">{children}</div>
      </RightSidePanelContent>
      {footer}
    </ErrorBoundary>
  )
}

const GenerateFixInner = memo(function GenerateFixInner({
  focusedGenerativeTask,
  suggestionsForPagination,
  commentsVersion,
  suggestionRequestId,
}: GenerateFixInnerProps) {
  const payload = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {path} = payload
  const taskId = focusedGenerativeTask.sourceId
  const sendEvent = useAnalytics()

  const {applyAllTaskSuggestionsToContent} = useFilesContext()
  const {getAppliedSuggestions} = useLocalSuggestionState()
  const appliedSuggestions = getAppliedSuggestions()
  const isApplied = appliedSuggestions.some(suggestion => suggestion === taskId)

  const {
    generatedFix,
    generateFix,
    isGeneratingFix,
    parsedDiff,
    blobData,
    loadBlobData,
    commentClassification,
    isClassifyingComments,
    hasError,
    retryRequests,
  } = useGenerateFix(focusedGenerativeTask, commentsVersion, suggestionRequestId)
  const {isAppliable, applyTooltip} = useTaskApplicableData(focusedGenerativeTask, blobData, parsedDiff)

  const isClassificationAvailable = !!commentClassification
  const isFixAvailable = !!commentClassification?.actionable && !!generatedFix
  const isThreadCondensed = isClassifyingComments || isGeneratingFix || isClassificationAvailable || isFixAvailable

  const isCommentOutdated = focusedGenerativeTask.outdated
  const hasCodeChangedSinceFix = generatedFix?.targetFileCommitOid !== focusedGenerativeTask?.comment?.commitOid
  const haveCommentsChangedSinceFix = generatedFix?.commentsVersion !== commentsVersion

  const applyFix = async () => {
    if (!focusedGenerativeTask) return

    let loadedBlobData = blobData

    // blob data might not be loaded if the user generates a fix then navigates away
    if (!loadedBlobData) {
      loadedBlobData = await loadBlobData()
    }

    // todo: better error handling
    if (!parsedDiff?.hunks || !parsedDiff.newFileName || !loadedBlobData) return
    const hunks = parsedDiff?.hunks.map(hunk => ({filePath: path, diff: {...hunk}}))

    const task = {...focusedGenerativeTask, suggestions: hunks}
    applyAllTaskSuggestionsToContent(task, [loadedBlobData])
    sendEvent('generated-fix.applied')
  }

  let footerPrimaryActionButton

  if (isFixAvailable && !hasCodeChangedSinceFix && !haveCommentsChangedSinceFix) {
    footerPrimaryActionButton = (
      <ApplyButton
        applyTooltip={applyTooltip}
        isAppliable={isAppliable}
        isApplied={isApplied}
        onApply={applyFix}
        variant="primary"
      />
    )
  } else if (isFixAvailable) {
    footerPrimaryActionButton = (
      <Button onClick={() => generateFix()} variant="primary">
        Generate a fix
      </Button>
    )
  } else {
    footerPrimaryActionButton = null
  }

  return (
    <Layout
      footer={
        <SuggestionFooter
          suggestionsForPagination={suggestionsForPagination}
          applyButton={footerPrimaryActionButton}
          showSuggestionApplied={isFixAvailable && !hasCodeChangedSinceFix && !haveCommentsChangedSinceFix && isApplied}
        />
      }
    >
      <PullThread
        comments={[focusedGenerativeTask.comment, ...focusedGenerativeTask.replies]}
        isCondensed={isThreadCondensed}
      />
      <GenerateFixResponse
        isGeneratingFix={isGeneratingFix}
        isClassifyingComments={isClassifyingComments}
        commentClassification={commentClassification}
        generatedFix={generatedFix}
        parsedDiff={parsedDiff}
        hasError={hasError}
        retryRequests={retryRequests}
        isCommentOutdated={isCommentOutdated}
        hasCodeChangedSinceFix={hasCodeChangedSinceFix}
        haveCommentsChangedSinceFix={haveCommentsChangedSinceFix}
        isApplied={isApplied}
        isAppliable={isAppliable}
        applyTooltip={applyTooltip}
        applyFix={applyFix}
        isFixAvailable={isFixAvailable}
      />
    </Layout>
  )
})

function GenerateFixResponse({
  isGeneratingFix,
  isClassifyingComments,
  commentClassification,
  generatedFix,
  parsedDiff,
  hasError,
  retryRequests,
  isCommentOutdated,
  hasCodeChangedSinceFix,
  haveCommentsChangedSinceFix,
  isApplied,
  isAppliable,
  applyTooltip,
  applyFix,
  isFixAvailable,
}: {
  isGeneratingFix: boolean
  isClassifyingComments: boolean
  commentClassification?: {
    actionable: boolean
    reasoning: string
  }
  generatedFix?: {
    description: string | undefined
    gitPatch: string
    targetFileCommitOid: string
    commentsVersion: string
  }
  parsedDiff?: {
    newFileName?: string
    hunks: Array<{
      oldStart: number
      oldLines: number
      newStart: number
      newLines: number
      lines: string[]
    }>
  }
  hasError: boolean
  retryRequests: () => void
  isCommentOutdated: boolean
  hasCodeChangedSinceFix: boolean
  haveCommentsChangedSinceFix: boolean
  isApplied: boolean
  isAppliable: boolean
  applyTooltip: string
  applyFix: () => void
  isFixAvailable: boolean
}) {
  const isGenerateFixEnabled = useFeatureFlag('hadron_comment_fix_generation')
  if (!isGenerateFixEnabled) {
    return
  }
  return (
    <>
      {!isClassifyingComments && !commentClassification?.actionable && !!commentClassification?.reasoning && (
        <div className="d-flex flex-column mt-3 gap-3">
          <CopilotComment comment={'No suggestions for this comment.'} />
        </div>
      )}
      {(isGeneratingFix || isClassifyingComments) && (
        <div className="d-flex flex-column">
          <span className="d-flex flex-row flex-items-center mt-3 gap-2">
            <CopilotBadge isLoading />
            <div className={clsx('color-fg-default f5 overflow-hidden', styles.actorName)}>Copilot</div>
            <span className="color-fg-muted">{isGeneratingFix ? 'generating suggestion...' : 'responding...'}</span>
          </span>
          {isGeneratingFix && <SkeletonDiffBlock />}
        </div>
      )}
      {!isGeneratingFix && isFixAvailable && (
        <div className="d-flex flex-column mt-3 gap-3">
          <CopilotComment comment={generatedFix?.description ?? ''} />
          {(hasCodeChangedSinceFix || isCommentOutdated) && (
            <div className="fgColor-muted f6">
              The following suggestion is outdated and cannot be automatically applied.
            </div>
          )}
          {parsedDiff?.newFileName && parsedDiff?.hunks && (
            <Diff
              fileName={parsedDiff.newFileName}
              lines={mapPatchToDiffLines({newFileName: parsedDiff.newFileName, hunks: parsedDiff.hunks})}
              outdated={haveCommentsChangedSinceFix || hasCodeChangedSinceFix || isCommentOutdated}
              headerActions={
                <ApplyButton
                  applyTooltip={applyTooltip}
                  disabled={hasCodeChangedSinceFix || isCommentOutdated}
                  isAppliable={isAppliable}
                  isApplied={isApplied}
                  onApply={applyFix}
                  size="small"
                />
              }
            />
          )}
        </div>
      )}
      {hasError && (
        <Banner
          title="Warning"
          hideTitle
          variant="warning"
          className="mt-3"
          description="Unexpected error occurred"
          secondaryAction={
            <Banner.SecondaryAction className="pt-2 pr-2" onClick={() => retryRequests()}>
              Retry
            </Banner.SecondaryAction>
          }
        />
      )}
    </>
  )
}
