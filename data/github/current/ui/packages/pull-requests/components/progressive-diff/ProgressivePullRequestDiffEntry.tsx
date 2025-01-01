import {memo, useEffect, useRef} from 'react'
import type {ProgressiveDiffEntry} from '../../types/progressive-diff-types'
import {useDiffEntry} from '../../page-data/loaders/use-diff-entries'
import {PullRequestDiff, type PullRequestDiffProps} from '../PullRequestDiff'
import {LazyDiffEntryLoadingSkeleton} from './LazyDiffEntryLoadingSkeleton'
import {EagerDiffEntryLoadingSkeleton} from './EagerDiffEntryLoadingSkeleton'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {PullRequestDiffEntryErrorFallback} from '../PullRequestDiffEntryErrorFallback'
import {DiffFileHeader} from '@github-ui/diff-file-header'
import styles from '@github-ui/diff-lines/Diff.module.css'
import {clsx} from 'clsx'
import {useDiffSummary} from '../../page-data/loaders/use-diff-summaries-data'
import {noop} from '@github-ui/noop'
import {HiddenDiffEntryLoadingSkeleton} from './HiddenDiffEntryLoadingSkeleton'

export type ProgressivePullRequestDiffEntryProps = {
  isSelectingLineOrRange?: boolean
  progressiveDiffEntry: ProgressiveDiffEntry
  onScrollToAndFocusEntry: (pathDigest: string) => void
} & Pick<
  PullRequestDiffProps,
  | 'basePath'
  | 'commentingEnabled'
  | 'commentBatchPending'
  | 'commentBoxConfig'
  | 'commentBoxSubject'
  | 'contextLinesURL'
  | 'currentUser'
  | 'diffManuallyExpanded'
  | 'focusedSearchResult'
  | 'headBranchName'
  | 'isSelected'
  | 'markerNavigationImplementation'
  | 'pullRequestState'
  | 'repository'
>

export const ProgressivePullRequestDiffEntry = memo(
  ProgressivePullRequestDiffEntryUnmemoized,
  (prevProps, nextProps) => {
    return (
      prevProps.progressiveDiffEntry.pathDigest === nextProps.progressiveDiffEntry.pathDigest &&
      prevProps.progressiveDiffEntry.renderMode === nextProps.progressiveDiffEntry.renderMode &&
      prevProps.isSelected === nextProps.isSelected &&
      prevProps.currentUser.splitPreference === nextProps.currentUser.splitPreference &&
      prevProps.currentUser.commentsPreference === nextProps.currentUser.commentsPreference &&
      prevProps.currentUser.lineSpacing === nextProps.currentUser.lineSpacing &&
      prevProps.commentBatchPending === nextProps.commentBatchPending
    )
    // TODO: add props for other cases where we want the diff entry to re-render
  },
)

function ProgressivePullRequestDiffEntryUnmemoized({
  basePath,
  commentBoxConfig,
  commentBoxSubject,
  commentBatchPending,
  commentingEnabled,
  contextLinesURL,
  currentUser,
  diffManuallyExpanded,
  focusedSearchResult,
  headBranchName,
  isSelected = false,
  isSelectingLineOrRange = false,
  markerNavigationImplementation,
  onScrollToAndFocusEntry,
  progressiveDiffEntry,
  pullRequestState,
  repository,
}: ProgressivePullRequestDiffEntryProps) {
  const {data: diffEntry} = useDiffEntry(basePath, progressiveDiffEntry.pathDigest)
  const {data: diffSummary} = useDiffSummary(basePath, progressiveDiffEntry.path)

  /*
   * Scroll to and focus the selected diff entry or line(s) on first visible render.
   * To ensure this effect only happens on first visible render, we use a ref to track if we have run it before.
   */
  const skipScrollToAndFocus = useRef(false)
  useEffect(() => {
    if (skipScrollToAndFocus.current) return

    // If entry is selected, don't scroll and focus until we've rendered something
    if (isSelected && progressiveDiffEntry.renderMode !== 'HIDE') {
      // If we're selecting an entry, not a line or range, scroll and focus right away, even if we're rendering a placeholder
      if (!isSelectingLineOrRange) {
        skipScrollToAndFocus.current = true
        onScrollToAndFocusEntry(progressiveDiffEntry.pathDigest)
      } else if (progressiveDiffEntry.renderMode === 'RENDER') {
        // If selecting a line or range, wait until the diff lines are actually rendered before trying to scroll and focus
        skipScrollToAndFocus.current = true
        onScrollToAndFocusEntry(progressiveDiffEntry.pathDigest)
      }
    }
  }, [
    isSelected,
    isSelectingLineOrRange,
    onScrollToAndFocusEntry,
    progressiveDiffEntry.pathDigest,
    progressiveDiffEntry.renderMode,
  ])

  if (
    progressiveDiffEntry.renderMode === 'HIDE' ||
    progressiveDiffEntry.renderMode === 'LAZY_AUTO_LOAD' ||
    progressiveDiffEntry.renderMode === 'EAGER_AUTO_LOAD'
  ) {
    let loadingSkeleton = <></>
    let approximateLineCount = diffSummary?.linesChanged ?? 5
    if (diffSummary?.changeType === 'REMOVED' || diffSummary?.changeType === 'DELETED') {
      approximateLineCount = 5
    }
    if (progressiveDiffEntry.renderMode === 'HIDE') {
      loadingSkeleton = (
        <HiddenDiffEntryLoadingSkeleton
          progressiveDiffEntry={progressiveDiffEntry}
          approximateLineCount={approximateLineCount}
        />
      )
    } else if (progressiveDiffEntry.renderMode === 'LAZY_AUTO_LOAD') {
      loadingSkeleton = (
        <LazyDiffEntryLoadingSkeleton
          progressiveDiffEntry={progressiveDiffEntry}
          approximateLineCount={approximateLineCount}
        />
      )
    } else if (progressiveDiffEntry.renderMode === 'EAGER_AUTO_LOAD') {
      loadingSkeleton = (
        <EagerDiffEntryLoadingSkeleton
          progressiveDiffEntry={progressiveDiffEntry}
          approximateLineCount={approximateLineCount}
        />
      )
    }

    return (
      <div
        role="region"
        id={`diff-${progressiveDiffEntry.pathDigest}`}
        className={clsx(styles.diffTargetable, styles.diff)}
        data-targeted={isSelected}
        key={`${progressiveDiffEntry.pathDigest}_${progressiveDiffEntry.path}`}
      >
        <div className={styles.diffHeaderWrapper}>
          <DiffFileHeader
            areLinesExpanded={false}
            canExpandOrCollapseLines={false}
            fileLinkHref={`#diff-${progressiveDiffEntry.pathDigest}`}
            canToggleRichDiff={false}
            linesAdded={diffSummary?.linesAdded ?? 0}
            linesChanged={diffSummary?.linesChanged ?? 0}
            linesDeleted={diffSummary?.linesDeleted ?? 0}
            newPath={progressiveDiffEntry.path}
            patchStatus={''}
            path={progressiveDiffEntry.path}
            onToggleExpandAllLines={noop}
            onToggleFileCollapsed={noop}
            onToggleDiffDisplay={noop}
          />
        </div>
        {loadingSkeleton}
      </div>
    )
  }

  if (!diffEntry) {
    return (
      <PullRequestDiffEntryErrorFallback
        linesAdded={0}
        linesChanged={0}
        linesDeleted={0}
        path={progressiveDiffEntry.path}
        pathDigest={progressiveDiffEntry.pathDigest}
        newTreeEntry={undefined}
        oldTreeEntry={undefined}
        status={'MODIFIED'}
      />
    )
  }

  return (
    <ErrorBoundary fallback={<PullRequestDiffEntryErrorFallback {...diffEntry} />}>
      <PullRequestDiff
        basePath={basePath}
        changeType={diffEntry.status}
        collapsed={diffEntry.collapsed ?? diffEntry.reviewed ?? false}
        commentBatchPending={commentBatchPending}
        commentBoxConfig={commentBoxConfig}
        commentBoxSubject={commentBoxSubject}
        commentingEnabled={commentingEnabled}
        contextLinesURL={contextLinesURL}
        currentUser={currentUser}
        diffContext="pr"
        diffLines={diffEntry.diffLines}
        diffManuallyExpanded={diffManuallyExpanded}
        diffMatches={diffEntry.diffMatches}
        diffSize={diffEntry.diffSize}
        focusedSearchResult={focusedSearchResult}
        headBranchName={headBranchName}
        helpUrl={diffEntry.helpUrl}
        isBinary={diffEntry.isBinary}
        isSelected={isSelected}
        isSubmodule={diffEntry.isSubmodule}
        isTooBig={diffEntry.isTooBig}
        linesAdded={diffEntry.linesAdded}
        linesChanged={diffEntry.linesChanged}
        linesDeleted={diffEntry.linesDeleted}
        markerNavigationImplementation={markerNavigationImplementation}
        newCommitOid={diffEntry.newCommitOid}
        newTreeEntry={diffEntry.newTreeEntry}
        objectId={diffEntry.objectId}
        oldCommitOid={diffEntry.oldCommitOid}
        oldTreeEntry={diffEntry.oldTreeEntry}
        path={diffEntry.path}
        pathDigest={diffEntry.pathDigest}
        pullRequestState={pullRequestState}
        repository={repository}
        reviewed={diffEntry.reviewed ?? false}
        richDiff={diffEntry.richDiff}
        status={diffEntry.status}
        submodule={diffEntry.submodule}
        truncatedReason={diffEntry.truncatedReason}
      />
    </ErrorBoundary>
  )
}
