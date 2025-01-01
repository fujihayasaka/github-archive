import {ChevronDownIcon, ChevronUpIcon, SearchIcon} from '@primer/octicons-react'
import {IconButton, TextInput} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {memo, useEffect, useRef, type MutableRefObject} from 'react'
import type {DiffMatchContent} from '../helpers/find-in-diff'
import type {FocusedSearchResult} from '../hooks/use-diff-search-results'
import styles from './DiffFind.module.css'
import {GlobalCommands, ScopedCommands} from '@github-ui/ui-commands'

export interface DiffFindProps {
  currentPathDigestIndex: MutableRefObject<number>
  searchTerm: string
  setSearchTerm: (searchTerm: string) => void
  focusedSearchResult: FocusedSearchResult | undefined
  currentIndex: number
  setCurrentIndex: (idx: number) => void
  setFocusedSearchResult: (idx: FocusedSearchResult | undefined) => void
  searchResults: Map<string, DiffMatchContent[]>
  scrollDiffCellIntoView: (diffToFocus: FocusedSearchResult | undefined) => void
}

/**
 * Using this component:
 *
 * In order to use the DiffFind component, you need to pass a few things into your usage of the DiffLines
 * component. First, in DiffFindOpenContext.tsx there is DiffFindOpenProvider which you need to supply
 * searchTerm and setSearchTerm to. The provider will allow you to consume whether or not this popover should be
 * rendered at any given time, and it keeps track of the search term between open/closed states.
 *
 * To get the search results, you must pass all of your DiffEntries, the search term, the web worker path, and a
 * piece of state which will be set whenever context lines are expanded to trigger a re-search into the
 * useDiffSearchResults hook. This hook will give you the search results and the currently focused search result
 * to then pass into the DiffLines component. The DiffLines component itself expects the focusedSearchResult to be
 * the index of the currently focused search result within the current path digest, or undefined if the currently
 * focused result is not within the current path digest. This prevents unnecessary rerenders.
 */
export const DiffFind = memo(function DiffFind({
  currentPathDigestIndex,
  searchTerm,
  searchResults,
  setSearchTerm,
  focusedSearchResult,
  currentIndex,
  setCurrentIndex,
  setFocusedSearchResult,
  scrollDiffCellIntoView,
}: DiffFindProps) {
  const currentKeyArray = useRef<string[]>([])
  const totalResultSize = useRef(0)
  const clearSearch = () => {
    setSearchTerm('')
    setFocusedSearchResult(undefined)
    currentPathDigestIndex.current = 0
  }

  const onChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    if (event.target.value) {
      setSearchTerm(event.target.value)
      setCurrentIndex(0)
    } else {
      clearSearch()
    }
  }

  const trailingActionElement = (
    <div className="d-flex flex-row flex-justify-center flex-items-center">
      {searchTerm && (
        <span className="text-small fgColor-subtle m-2 text-center">
          {searchResults.size === 0 || focusedSearchResult === undefined ? 0 : currentIndex + 1}/
          {totalResultSize.current}
        </span>
      )}
      {!searchTerm && <span className="text-small fgColor-subtle m-2 text-center pr-4">&nbsp;</span>}
      {searchTerm && (
        <>
          <IconButton
            size="small"
            variant="invisible"
            onClick={() => {
              jumpToResult(-1)
            }}
            icon={ChevronUpIcon}
            aria-label="Up"
            data-testid="up-search"
          />
          <IconButton
            size="small"
            variant="invisible"
            onClick={() => {
              jumpToResult(1)
            }}
            icon={ChevronDownIcon}
            aria-label="Down"
            data-testid="down-search"
          />
        </>
      )}
    </div>
  )

  const jumpToResult = (direction: number) => {
    if (focusedSearchResult === undefined || focusedSearchResult.pathDigest === '') {
      currentPathDigestIndex.current = 0
      const initialResult = {
        pathDigest: currentKeyArray.current[0] ?? '',
        indexWithinDigest: 0,
      }
      setFocusedSearchResult(initialResult)
      return
    }
    const tempFocusedResult = focusedSearchResult
    if (direction === 1) {
      setCurrentIndex(currentIndex === totalResultSize.current - 1 ? 0 : currentIndex + 1)
      // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
      if (focusedSearchResult.indexWithinDigest === searchResults.get(focusedSearchResult.pathDigest)!.length - 1) {
        currentPathDigestIndex.current = currentPathDigestIndex.current + 1
        if (currentPathDigestIndex.current === currentKeyArray.current.length) {
          currentPathDigestIndex.current = 0
        }
        tempFocusedResult.pathDigest = currentKeyArray.current[currentPathDigestIndex.current] ?? ''
        tempFocusedResult.indexWithinDigest = 0
        //move on to the next path digest or wrap around if at the end
      } else {
        //not at the end of the current path digest

        tempFocusedResult.indexWithinDigest = tempFocusedResult.indexWithinDigest + 1
      }
    } else {
      setCurrentIndex(currentIndex === 0 ? totalResultSize.current - 1 : currentIndex - 1)
      if (focusedSearchResult.indexWithinDigest === 0) {
        currentPathDigestIndex.current = currentPathDigestIndex.current - 1
        if (currentPathDigestIndex.current === -1) {
          currentPathDigestIndex.current = currentKeyArray.current.length - 1
        }
        tempFocusedResult.pathDigest = currentKeyArray.current[currentPathDigestIndex.current] ?? ''
        // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
        tempFocusedResult.indexWithinDigest = searchResults.get(tempFocusedResult.pathDigest)!.length - 1
        //move on to the next path digest or wrap around if at the end
      } else {
        //can stay within the same current path digest
        tempFocusedResult.indexWithinDigest = tempFocusedResult.indexWithinDigest - 1
      }
    }
    setFocusedSearchResult(tempFocusedResult)
  }

  useEffect(() => {
    currentKeyArray.current = Array.from(searchResults.keys())
    currentPathDigestIndex.current = 0
    const initialResult = {
      pathDigest: currentKeyArray.current[0] ?? '',
      indexWithinDigest: 0,
    }
    setFocusedSearchResult(initialResult)
    let incSize = 0
    for (const result of searchResults.values()) {
      incSize += result.length
    }
    totalResultSize.current = incSize
  }, [currentPathDigestIndex, searchResults, searchResults.size, setFocusedSearchResult])

  useEffect(() => {
    if (searchResults.size > 0 && focusedSearchResult !== undefined) {
      scrollDiffCellIntoView(focusedSearchResult)
    }

    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchResults, focusedSearchResult, currentIndex])

  return (
    <div className={styles.defaultStyles}>
      <GlobalCommands
        commands={{
          'pull-requests-diff-view:jump-to-next-result-alternate': () => jumpToResult(1),
          'pull-requests-diff-view:jump-to-previous-result-alternate': () => jumpToResult(-1),
        }}
      />
      <ScopedCommands
        commands={{
          'pull-requests-diff-view:jump-to-next-result': () => jumpToResult(1),
          'pull-requests-diff-view:jump-to-previous-result': () => jumpToResult(-1),
        }}
      >
        <TextInput
          className="border-0 box-shadow-none"
          style={{width: '100%'}}
          validationStatus={totalResultSize.current > 1000 ? 'error' : undefined}
          type="text"
          leadingVisual={() => <Octicon icon={SearchIcon} aria-hidden="true" />}
          autoComplete="off"
          name="Find in commit input"
          aria-label="Search within code"
          placeholder="Search within code"
          value={searchTerm}
          onChange={onChange}
          block
          trailingAction={trailingActionElement}
        />
      </ScopedCommands>
    </div>
  )
})
