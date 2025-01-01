import type {Repository} from '@github-ui/current-repository'
import {getFileExtension} from '@github-ui/diff-file-tree/diff-file-tree-helpers'
import {DiffFind, type FocusedSearchResult, useDiffSearchResults} from '@github-ui/diff-lines'
import {parseDiffHash} from '@github-ui/diff-lines/document-hash-helpers'
import {useSelectedDiffHash} from '@github-ui/diff-lines/use-selected-diff-hash'
import {
  defaultViewSettings,
  useDiffViewSettingsData,
  useWhitespacePreference,
} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'
import type {DiffLineSpacingPreference} from '@github-ui/diff-view-settings/types'
import {noop} from '@github-ui/noop'
import {diffIndexPath} from '@github-ui/paths'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ssrSafeDocument, ssrSafeLocation, ssrSafeWindow} from '@github-ui/ssr-utils'
import {defaultRangeExtractor, useVirtualWindowDynamic} from '@github-ui/use-virtual/window'
import {Flash} from '@primer/react'
import type React from 'react'
import {memo, useCallback, useEffect, useRef, useState} from 'react'

import {useCommitsAppPayload} from '../../hooks/use-commits-app-payload'
import {useLoadDeferredDiffs} from '../../hooks/use-load-deferred-diffs'
import type {CommitAppPayload, CommitPayload, DiffEntryDataWithExtraInfo, HeaderInfo} from '../../types/commit-types'
import {forceAnnouncementToScreenReaders} from '../../utils/force-announcement-to-screen-readers'
import {VirtualizedBanner} from './banners/VirtualizedBanner'
import {Diff} from './Diff'
import {DiffsHeader} from './DiffsHeader'
import {LoadingContentBlock} from './LoadingContentBlock'
import {virtualizationFileLimit} from './SSRDiffs'

interface DiffsProps {
  totalFileCount: number
  diffEntryData: DiffEntryDataWithExtraInfo[]
  contextLinePathURL: string
  unselectedFileExtensions?: Set<string>
  repo: Repository
  oid: string
  ignoreWhitespace: boolean
  filterTerm: string
  searchTerm: string
  setSearchTerm: (searchTerm: string) => void
  treeToggleElement: JSX.Element
  isTreeExpanded: boolean
  headerInfo: HeaderInfo
}

/**
 * Calculates the height of a diff based on the number of lines and threads.
 *
 * This is an estimate, and we use it to pre-calculate the height of virtual diff placeholders so we get a fairly
 * accurate scroll height before every diff has been rendered.
 *
 */
function calculateDiffHeight(lineSpacing: DiffLineSpacingPreference, diff?: NonNullableDiff) {
  let height = baseDiffHeight
  if (diff?.collapsed) {
    return height
  }

  if (diff?.newTreeEntry?.isGenerated && !diff?.diffManuallyExpanded) {
    return generatedFileDiffHeight
  }

  if (diff?.isTooBig) {
    return tooLargeDiffHeight
  }

  if (diff?.diffLines) {
    if (lineSpacing === 'compact') {
      height += diff.diffLines.length * compactEstimatedLineHeight
    } else {
      height += diff.diffLines.length * estimatedLineHeight
    }
  }

  //if we have more context lines at the bottom of the file, account for the bottom context line element
  if (
    diff?.newTreeEntry?.lineCount &&
    diff.newTreeEntry.lineCount > (diff?.diffLines[diff?.diffLines.length - 1]?.right ?? 0)
  ) {
    height += singleDirectionExpansionHeight
  }
  return height
}

type NonNullableDiff = NonNullable<DiffEntryDataWithExtraInfo>
const headerHeight = 41
const headerWrapperPadding = 16
const baseDiffHeight = headerHeight + headerWrapperPadding
// This is just the empty line minimum line height
const estimatedLineHeight = 25
const compactEstimatedLineHeight = 20

// includes the base height along with a placeholder saying we can't show the diff.
const tooLargeDiffHeight = 104

//includes base height and the placeholder with the load diff option
const generatedFileDiffHeight = 199

//height of context lines expansion with only one direction
const singleDirectionExpansionHeight = 32

//height of context lines expansion with both directions
//TODO: determine if we want to iterate through every single line to determine if we should use 32 or 40px as the estimate,
//or do we just overestimate and do 40. If we underestimate, the comment box at the bottom overlaps with some diffs, hence
//the functionality rework in this PR
// eslint-disable-next-line unused-imports/no-unused-vars
const bothDirectionExpansionHeight = 40

const stickyHeaderHeight = 60 // height to be used when scrolling, the 4px difference looks nicer

export const Diffs = memo(DiffsUnmemoized)

export function DiffsUnmemoized({
  totalFileCount,
  diffEntryData,
  contextLinePathURL,
  unselectedFileExtensions,
  repo,
  oid,
  ignoreWhitespace,
  filterTerm,
  searchTerm,
  setSearchTerm,
  isTreeExpanded,
  treeToggleElement,
  headerInfo,
}: DiffsProps) {
  const selectedPathDigest = useSelectedDiffHash()
  let {data: diffViewSettings} = useDiffViewSettingsData()
  if (diffViewSettings === undefined) diffViewSettings = defaultViewSettings
  const lineSpacing = diffViewSettings.lineSpacing
  const userWhitespaceParam = useWhitespacePreference(diffViewSettings.hideWhitespace)
  const payload = useRoutePayload<CommitPayload>()

  // Triggers a re-render because the object literal will be a new object every time
  const resetVirtualizerHeight = useCallback(() => recalculateWhichDiffsShouldBeShown({}), [])
  //we don't care about the value of the state, it is purely used to trigger a re-render
  const [usedToRecalculateWhichDiffsAreShown, recalculateWhichDiffsShouldBeShown] = useState({})
  const diffEntriesToUse = useRef(diffEntryData)
  const {findInDiffWorkerPath} = useCommitsAppPayload()
  const allDiffEntriesWithNoFiltering = useRef(diffEntryData)
  const shouldVirtualize = useRef(totalFileCount > virtualizationFileLimit)
  const errorFlashRef = useRef<HTMLDivElement | null>(null)
  const [shouldIgnoreWhitespace, setShouldIgnoreWhitespace] = useState(userWhitespaceParam)
  const currentPathDigestIndex = useRef(0)
  const currentFilteredSize = useRef(totalFileCount)
  const [oidToUse, setOidToUse] = useState(oid)
  const {focusedSearchResult, setFocusedSearchResult, searchResults, currentIndex, setCurrentIndex} =
    useDiffSearchResults(
      diffEntriesToUse.current,
      searchTerm,
      findInDiffWorkerPath,
      usedToRecalculateWhichDiffsAreShown,
    )

  function onOptionCollapseToggle(collapsedState: boolean) {
    for (const diffEntry of diffEntriesToUse.current) {
      diffEntry.collapsed = collapsedState
    }
    resetVirtualizerHeight()
  }

  useEffect(() => {
    if (unselectedFileExtensions && unselectedFileExtensions.size > 0) {
      diffEntriesToUse.current = allDiffEntriesWithNoFiltering.current.filter(
        diffEntry => !unselectedFileExtensions.has(getFileExtension(diffEntry.path)),
      )
    } else {
      diffEntriesToUse.current = allDiffEntriesWithNoFiltering.current
    }

    if (filterTerm) {
      diffEntriesToUse.current = diffEntriesToUse.current.filter(diffEntry =>
        diffEntry.path.toLowerCase().includes(filterTerm.toLowerCase()),
      )
    }
    if (currentFilteredSize.current !== diffEntriesToUse.current.length) {
      const filteredCount = diffEntriesToUse.current.length
      const announcementText = `${filteredCount} file${filteredCount === 1 ? '' : 's'} remain${
        filteredCount === 1 ? 's' : ''
      }`
      if (filteredCount !== 0) {
        forceAnnouncementToScreenReaders(announcementText, 150)
      }
    }
    currentFilteredSize.current = diffEntriesToUse.current.length

    shouldVirtualize.current = diffEntriesToUse.current.length > virtualizationFileLimit
    resetVirtualizerHeight()
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [unselectedFileExtensions?.size, filterTerm])

  useEffect(() => {
    diffEntriesToUse.current = diffEntryData
    allDiffEntriesWithNoFiltering.current = diffEntryData
    shouldVirtualize.current = totalFileCount > virtualizationFileLimit
    resetVirtualizerHeight()
    setShouldIgnoreWhitespace(ignoreWhitespace)
    setOidToUse(oid)
    // reset when we soft nav to a new commit
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [payload.path])

  const scrollDiffCellIntoView = (focusedResult: FocusedSearchResult | undefined) => {
    const indexOfDiff = getDiffWithPathDigest(focusedResult?.pathDigest ?? '', diffEntriesToUse.current)

    if (indexOfDiff === -1) {
      //something went wrong finding the diff, just return and don't do anything
      return
    }
    virtualizer.scrollToIndex(indexOfDiff, {align: 'center'})
    requestAnimationFrame(() => {
      scrollToSearchElement(focusedResult?.indexWithinDigest ?? 0, focusedResult?.pathDigest ?? '')
    })
  }

  const appPayload = useAppPayload<CommitAppPayload>()
  const url = diffIndexPath({
    owner: payload.repo.ownerLogin,
    repo: payload.repo.name,
    sha1: payload.commit.sha1,
    sha2: payload.commit.sha2,
    oid: payload.commit.oid,
  })
  const extraDiffs = useLoadDeferredDiffs(
    payload.asyncDiffLoadInfo.byteCount,
    payload.asyncDiffLoadInfo.lineShownCount,
    payload.asyncDiffLoadInfo.startIndex,
    url,
    payload.moreDiffsToLoad,
    ignoreWhitespace,
  )

  useEffect(() => {
    const concatenatedDiffEntries = diffEntriesToUse.current.concat(extraDiffs.extraDiffEntries)

    if (unselectedFileExtensions && unselectedFileExtensions.size > 0) {
      diffEntriesToUse.current = concatenatedDiffEntries.filter(
        diffEntry => !unselectedFileExtensions.has(getFileExtension(diffEntry.path)),
      )
    } else {
      diffEntriesToUse.current = concatenatedDiffEntries
    }

    if (filterTerm) {
      diffEntriesToUse.current = diffEntriesToUse.current.filter(diffEntry =>
        diffEntry.path.toLowerCase().includes(filterTerm.toLowerCase()),
      )
    }

    allDiffEntriesWithNoFiltering.current = concatenatedDiffEntries
    resetVirtualizerHeight()

    //run this when the extra diffs finish loading
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [extraDiffs.extraDiffEntries.length])

  const diffsParentRef = useRef<HTMLDivElement>(null)

  //TODO: the ideal scenario would probably be splitting this up into diffsVirtualized and diffsNotVirtualized so
  //we don't have to do the virtualizer setup work unnecessarily, but then we have a million code paths again...
  //idk
  const virtualizer = useVirtualWindowDynamic({
    // additionalScrollOffset: -totalStickyHeaderHeight,
    parentRef: diffsParentRef,
    shouldUseScrollRef: shouldVirtualize.current,
    size: isTreeExpanded ? 0 : diffEntriesToUse.current.length,
    estimateSize: useCallback(
      (index: number) => {
        if (!shouldVirtualize.current) return 0
        let height = calculateDiffHeight(lineSpacing, diffEntriesToUse.current[index])
        // if we are the first diff, we need to account for the header
        if (index === 0) {
          height -= headerWrapperPadding
        }
        return height
      },
      // eslint-disable-next-line react-hooks/react-compiler
      // eslint-disable-next-line react-hooks/exhaustive-deps
      [diffEntriesToUse.current.length, usedToRecalculateWhichDiffsAreShown],
    ),
    // inspect the range of materialized items, and ensure that any patch with focus within stays in the virtual window
    rangeExtractor(range) {
      if (!shouldVirtualize.current) return defaultRangeExtractor(range)
      const hash = ssrSafeLocation.hash.substring(1)
      const fileDigest = parseDiffHash(hash)
      const focusedPathDigest = document
        .querySelector('[data-path-digest]:focus-within')
        ?.getAttribute('data-path-digest')

      const focusedDiffIndex = diffEntriesToUse.current.findIndex(patch => patch.pathDigest === focusedPathDigest)
      const anchoredDiffIndex = diffEntriesToUse.current.findIndex(patch => fileDigest?.endsWith(patch.pathDigest))

      if (focusedDiffIndex < 0 && anchoredDiffIndex < 0) {
        return defaultRangeExtractor(range)
      }

      const nextRange = new Set([
        ...defaultRangeExtractor(range),
        ...[focusedDiffIndex, anchoredDiffIndex].filter(index => index > -1),
      ])
      return Array.from(nextRange).sort((a, b) => a - b)
    },
  })

  useEffect(() => {
    const isHighlightingRightRow = selectedPathDigest.includes('R')
    const isHighlightingLeftRow = selectedPathDigest.includes('L')
    const isHighlightingRow = isHighlightingLeftRow || isHighlightingRightRow
    const pathDigest = isHighlightingRow
      ? isHighlightingLeftRow
        ? selectedPathDigest.split('L')[0]
        : selectedPathDigest.split('R')[0]
      : selectedPathDigest
    const indexOfDiff = getDiffWithPathDigest(pathDigest ?? selectedPathDigest, diffEntriesToUse.current)
    if (indexOfDiff === -1) {
      if (extraDiffs.error && errorFlashRef !== null) {
        const flashComponent = errorFlashRef.current?.childNodes[0] as HTMLDivElement
        flashComponent?.focus()
        flashComponent?.scrollIntoView({block: 'center'})
      }
      return
    }

    if (shouldVirtualize.current) {
      virtualizer.scrollToIndex(indexOfDiff, {align: 'center'})
      requestAnimationFrame(() => {
        if (isHighlightingRow && focusRowElement(diffsParentRef, selectedPathDigest)) {
          //if we are in here, then nothing else to do, otherwise we couldn't find the row (was a context row)
          //to highlight so default to just highlighting the file itself
        } else {
          const collapseButton = diffsParentRef.current?.querySelectorAll(
            `[aria-label="collapse file: ${diffEntriesToUse.current[indexOfDiff]?.path}"]`,
          )
          if (collapseButton && collapseButton.length === 1) {
            const collapseButtonToFocus = collapseButton[0]! as HTMLElement
            collapseButtonToFocus.focus()
          }
        }
      })
    } else {
      if (isHighlightingRow && focusRowElement(diffsParentRef, selectedPathDigest)) {
        //if we are in here, then nothing else to do, otherwise we couldn't find the row (was a context row)
        //to highlight so default to just highlighting the file itself
      } else {
        const allDiffLinesElements = diffsParentRef.current?.querySelectorAll(`[data-diff-anchor=diff-${pathDigest}]`)
        if (allDiffLinesElements && allDiffLinesElements.length === 1) {
          const elementToScrollTo = allDiffLinesElements[0]! as HTMLElement
          const yOffset =
            elementToScrollTo.getBoundingClientRect().top +
            (ssrSafeWindow?.scrollY ?? 0) -
            baseDiffHeight -
            stickyHeaderHeight
          ssrSafeWindow?.scrollTo(0, yOffset)
          const collapseButton = diffsParentRef.current?.querySelectorAll(
            `[aria-label="collapse file: ${diffEntriesToUse.current[indexOfDiff]?.path}"]`,
          )
          if (collapseButton && collapseButton.length === 1) {
            const collapseButtonToFocus = collapseButton[0]! as HTMLElement
            collapseButtonToFocus.focus()
          }
        }
      }
    }
    //if the extra diffs loaded we want to run this again to check if the selected path digest was within
    //the diffs which just returned
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedPathDigest, extraDiffs])

  const noFilesSelected = !shouldVirtualize.current && diffEntriesToUse.current.length === 0
  const noFilesSelectedText = 'There are no files selected for viewing'

  const searchBox = (
    <DiffFind
      currentPathDigestIndex={currentPathDigestIndex}
      searchTerm={searchTerm}
      focusedSearchResult={focusedSearchResult}
      currentIndex={currentIndex}
      setCurrentIndex={setCurrentIndex}
      setFocusedSearchResult={setFocusedSearchResult}
      setSearchTerm={setSearchTerm}
      searchResults={searchResults}
      scrollDiffCellIntoView={scrollDiffCellIntoView}
    />
  )

  return (
    <div data-hpc ref={diffsParentRef}>
      {shouldVirtualize.current && <VirtualizedBanner />}
      <DiffsHeader treeToggleElement={treeToggleElement} headerInfo={headerInfo} searchBox={searchBox} />

      {!shouldVirtualize.current &&
        diffEntriesToUse.current.map((diffEntry, index) => {
          let diffMatches = undefined
          let currentlyFocusedResult = undefined
          if (searchResults.has(diffEntry?.pathDigest ?? '')) {
            //we have a match within this diff, highlight it
            diffMatches = searchResults.get(diffEntry?.pathDigest ?? '') ?? []
          }
          //we only care about the focused search result if WE are the focused search result, which happens
          //in this condition
          if (focusedSearchResult && diffEntry?.pathDigest === focusedSearchResult?.pathDigest) {
            currentlyFocusedResult = focusedSearchResult?.indexWithinDigest ?? -1
          }
          return (
            <div
              key={diffEntry.pathDigest}
              style={{
                paddingTop: index === 0 ? 0 : 16,
                left: 3,
                right: 3,
              }}
            >
              <Diff
                diffEntryData={diffEntriesToUse}
                diffMatches={diffMatches}
                focusedSearchResult={currentlyFocusedResult}
                onOptionCollapseToggle={onOptionCollapseToggle}
                index={index}
                contextLinePathURL={contextLinePathURL}
                recalcTotalHeightOfVirtualWindow={noop}
                repo={repo}
                helpUrl={appPayload.helpUrl}
                oid={oidToUse}
                ignoreWhitespace={shouldIgnoreWhitespace}
              />
            </div>
          )
        })}

      <div role="alert" className="sr-only">
        {noFilesSelected && <h3 className="d-flex flex-justify-center">{noFilesSelectedText}</h3>}
      </div>

      {shouldVirtualize.current && (
        <div style={{height: virtualizer.totalSize, width: '100%', position: 'relative'}}>
          {virtualizer.virtualItems.map(virtualRow => {
            const diffEntry = diffEntriesToUse.current[virtualRow.index]
            let diffMatches = undefined
            let currentlyFocusedResult = undefined
            if (searchResults.has(diffEntry?.pathDigest ?? '')) {
              //we have a match within this diff, highlight it
              diffMatches = searchResults.get(diffEntry?.pathDigest ?? '') ?? []
            }
            //we only care about the focused search result if WE are the focused search result, which happens
            //in this condition
            if (focusedSearchResult && diffEntry?.pathDigest === focusedSearchResult?.pathDigest) {
              currentlyFocusedResult = focusedSearchResult?.indexWithinDigest ?? -1
            }

            if (!diffEntry) return null

            return (
              <div
                key={diffEntry.pathDigest}
                ref={virtualRow.measureRef}
                data-key={virtualRow.key}
                style={{
                  position: 'absolute',
                  paddingTop: virtualRow.index === 0 ? 0 : 16,
                  left: 3,
                  right: 3,
                  transform: `translateY(${virtualRow.start}px)`,
                }}
              >
                <Diff
                  diffMatches={diffMatches}
                  focusedSearchResult={currentlyFocusedResult}
                  diffEntryData={diffEntriesToUse}
                  index={virtualRow.index}
                  contextLinePathURL={contextLinePathURL}
                  onOptionCollapseToggle={onOptionCollapseToggle}
                  recalcTotalHeightOfVirtualWindow={resetVirtualizerHeight}
                  headerStickyOffset={-virtualRow.start}
                  helpUrl={appPayload.helpUrl}
                  repo={repo}
                  oid={oidToUse}
                  ignoreWhitespace={shouldIgnoreWhitespace}
                  virtualizerScrollTo={virtualizer.scrollToIndex}
                />
              </div>
            )
          })}
        </div>
      )}
      {payload.moreDiffsToLoad && (
        <>
          {extraDiffs.loading && <LoadingContentBlock />}
          {extraDiffs.error && (
            <div style={{justifyContent: 'center', paddingTop: '16px'}} ref={errorFlashRef}>
              <Flash variant="danger" tabIndex={0}>
                <div className={'d-flex flex-items-center'} style={{justifyContent: 'center'}}>
                  There was a problem loading the remainder of the diff.
                </div>
              </Flash>
            </div>
          )}
        </>
      )}
    </div>
  )
}

function getDiffWithPathDigest(pathDigest: string, diffEntries: DiffEntryDataWithExtraInfo[]) {
  for (let i = 0; i < diffEntries.length; i++) {
    if (pathDigest === diffEntries[i]?.pathDigest) return i
  }
  return -1
}

function focusRowElement(diffsParentRef: React.RefObject<HTMLDivElement>, selectedPathDigest: string) {
  const lineToHighlight = diffsParentRef.current?.querySelectorAll(`[data-line-anchor=diff-${selectedPathDigest}]`)
  if (lineToHighlight && lineToHighlight.length === 1) {
    const collapseButtonToFocus = lineToHighlight[0]! as HTMLElement
    collapseButtonToFocus.focus()
    return true
  }
  return false
}

function scrollToSearchElement(indexToScrollTo: number, pathDigest: string) {
  const lineToHighlight = ssrSafeDocument?.getElementById(`match-${pathDigest}-${indexToScrollTo}`)
  if (lineToHighlight) {
    lineToHighlight.scrollIntoView({block: 'center'})
  }
}
