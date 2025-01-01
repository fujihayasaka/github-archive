import {memo, useCallback, useMemo, useRef, useState} from 'react'
import type {DiffUser, PullRequestState} from '@github-ui/diff-lines/types'
import {DiffPlaceholder} from '@github-ui/diffs/DiffParts'
import type {CommentingImplementation, MarkerNavigationImplementation} from '@github-ui/conversations'
import {FilesChangedFilterBlankSlate} from './FilesChangedFilterBlankSlate'
import {
  isSelectingDiffLineOrRange,
  parsePathDigestWithoutLineNumbers,
} from '@github-ui/diff-lines/document-hash-helpers'
import {useSelectedFullDiffHash} from '@github-ui/diff-lines/use-selected-diff-hash'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import type {Repository} from '@github-ui/current-repository'
import {usePrefersReducedMotion} from '@github-ui/use-prefers-reduced-motion'
import type {PullRequestFileTreeDiff} from '../page-data/payloads/file-tree'
import {ProgressivePullRequestDiffEntry} from './progressive-diff/ProgressivePullRequestDiffEntry'
import {useProgressiveDiffStore} from '../stores/ProgressiveDiffStore'
import {EmptyPullRequestBlankSlate} from './EmptyPullRequestBlankSlate'
import {useDiffSummaries} from '../page-data/loaders/use-diff-summaries-data'
import type {RepoSubject} from '@github-ui/comment-box/subject'

export const SHOW_WHIMSY_THRESHOLD = 15

export interface PullRequestDiffsListProps {
  basePath: string
  commentBoxConfig: CommentingImplementation['commentBoxConfig']
  commentBoxSubject?: RepoSubject
  contextLinesURL: string
  currentUser: DiffUser
  filteredDiffSummaries: PullRequestFileTreeDiff[]
  headBranchName: string
  pullRequestState: PullRequestState
  repository: Pick<Repository, 'id' | 'name' | 'ownerLogin'>
  commentBatchPending: boolean
  endOfDiffsImagePath?: string | undefined
}

const headerHeight = 41
const headerWrapperPadding = 16
const baseDiffHeight = headerHeight + headerWrapperPadding
const stickyHeaderHeight = 60 // height to be used when scrolling, the 4px difference looks nicer
export const PullRequestDiffsList = memo(PullRequestDiffsListUnmemoized)

function PullRequestDiffsListUnmemoized({
  basePath,
  commentBoxConfig,
  commentBoxSubject,
  contextLinesURL,
  currentUser,
  filteredDiffSummaries,
  headBranchName,
  pullRequestState,
  repository,
  commentBatchPending,
  endOfDiffsImagePath,
}: PullRequestDiffsListProps) {
  const [diffManuallyExpanded, __] = useState(false)
  const selectedFullDiffHash = useSelectedFullDiffHash()
  const selectedPathDigest = parsePathDigestWithoutLineNumbers(selectedFullDiffHash) ?? ''
  const isSelectingLineOrRange = isSelectingDiffLineOrRange(selectedFullDiffHash)

  const diffsParentRef = useRef<HTMLDivElement>(null)
  const markerNavigationImplementation: MarkerNavigationImplementation = {
    incrementActiveMarker: () => {},
    decrementActiveMarker: () => {},
    filteredMarkers: [],
    onActivateGlobalMarkerNavigation: () => {},
    activeGlobalMarkerID: undefined,
  }

  const diffEntries = useProgressiveDiffStore(s => s.entries)

  /*
   * Scroll logic for progressive diffs.
   */
  const targetableEntriesRef = useRef<Map<string, HTMLElement>>(new Map())
  const getTargetableEntriesMap = useCallback(() => {
    return targetableEntriesRef.current
  }, [])

  const initialRenderRef = useRef(true)
  const onScrollToAndFocusEntry = (pathDigest: string) => {
    const map = getTargetableEntriesMap()
    const node = map.get(pathDigest)
    if (!node) return

    // By default, scroll to the entry and focus its toggle button
    let elementToScrollTo: HTMLElement | null = node
    let elementToFocus: HTMLElement | null = node.querySelector<HTMLButtonElement>(`button`)

    // If line or range is selected, scroll to first line and focus
    if (isSelectingLineOrRange) {
      const row = node.querySelector<HTMLElement>(`[data-line-anchor=diff-${selectedFullDiffHash}]`)
      if (row) {
        elementToScrollTo = row
        elementToFocus = elementToScrollTo
      }
    } else if (!initialRenderRef.current) {
      // if selecting the full entry, only scroll to it on initial render
      // after that, scroll to elements works as expected with targetable entries with html + css
      elementToScrollTo = null
    }

    if (elementToScrollTo) {
      const scrollY = ssrSafeWindow?.scrollY ?? 0
      const yOffset = elementToScrollTo.getBoundingClientRect().top + scrollY - baseDiffHeight - stickyHeaderHeight
      ssrSafeWindow?.scrollTo({top: yOffset, left: 0})
    }

    if (elementToFocus) {
      elementToFocus.focus()
    }

    initialRenderRef.current = false
  }

  const {data: diffSummaries} = useDiffSummaries(basePath)

  const entriesToRender = useMemo(() => {
    return diffEntries.filter(entry => {
      return filteredDiffSummaries.some(diffSummary => diffSummary.path === entry.path)
    })
  }, [diffEntries, filteredDiffSummaries])

  const totalVisibleEntries = entriesToRender.length

  /*
   * Empty state for PRs with no changed files.
   * See below for separate empty state for empty filter results.
   */
  if (diffSummaries === undefined || diffSummaries?.length === 0) {
    return <EmptyPullRequestBlankSlate />
  }
  /*
   * Empty state
   * Show a blank slate if nothing matches currently applied filters.
   */
  if (filteredDiffSummaries.length === 0) {
    return <FilesChangedFilterBlankSlate />
  }

  return (
    <div ref={diffsParentRef} data-hpc className="d-flex flex-column gap-3">
      {entriesToRender.map(progressiveDiffEntry => {
        return (
          <div
            key={progressiveDiffEntry.pathDigest}
            ref={(node: HTMLDivElement) => {
              const map = getTargetableEntriesMap()
              if (node) {
                map.set(progressiveDiffEntry.pathDigest, node)
              } else {
                map.delete(progressiveDiffEntry.pathDigest)
              }
            }}
          >
            <ProgressivePullRequestDiffEntry
              basePath={basePath}
              commentBatchPending={commentBatchPending}
              commentBoxConfig={commentBoxConfig}
              commentBoxSubject={commentBoxSubject}
              commentingEnabled
              contextLinesURL={contextLinesURL}
              currentUser={currentUser}
              diffManuallyExpanded={diffManuallyExpanded}
              headBranchName={headBranchName}
              isSelected={progressiveDiffEntry.pathDigest === selectedPathDigest}
              isSelectingLineOrRange={isSelectingLineOrRange}
              markerNavigationImplementation={markerNavigationImplementation}
              onScrollToAndFocusEntry={onScrollToAndFocusEntry}
              progressiveDiffEntry={progressiveDiffEntry}
              pullRequestState={pullRequestState}
              repository={repository}
            />
          </div>
        )
      })}
      <EndOfDiffsMessage imagePath={endOfDiffsImagePath} totalVisibleEntries={totalVisibleEntries} />

      {/* DiffPlaceholder is used for the skeleton placeholder when a diff isn't loaded.
      It needs to be somewhere on the page so that it can be drawn from within the diff lines component. */}
      <DiffPlaceholder />
    </div>
  )
}

/*
 * Whimsy
 * Show a fun image at the end of the diff list if there's enough visible entries and the user has not enabled reduced motion.
 * TODO: Create a static image to render in place of current GIF if user prefers reduced motion.
 */
const EndOfDiffsMessage = memo(function EndOfDiffsMessage({
  imagePath,
  imageAlt = 'GIF of an octocat high fiving another octocat',
  totalVisibleEntries = 0,
}: {
  imagePath?: string
  imageAlt?: string
  totalVisibleEntries?: number
}) {
  // Reduced motion setting is based on system settings, not dotcom user settings.
  const prefersReducedMotion = usePrefersReducedMotion()

  if (!imagePath) return
  if (prefersReducedMotion) return
  if (totalVisibleEntries <= SHOW_WHIMSY_THRESHOLD) return

  return (
    <div className="d-flex flex-justify-center flex-column text-center flex-items-center py-8 px-3">
      <img src={imagePath} alt={imageAlt} style={{height: '56px'}} />
      <span className="fgColor-muted mt-2">You made it to the end!</span>
    </div>
  )
})
