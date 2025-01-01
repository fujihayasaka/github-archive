import {useFileQueryContext} from '@github-ui/code-view-shared/contexts/FileQueryContext'
import {useFilesPageInfo} from '@github-ui/code-view-shared/contexts/FilesPageInfoContext'
import {useReposAnalytics} from '@github-ui/code-view-shared/hooks/use-repos-analytics'
import {useTreeList} from '@github-ui/code-view-shared/hooks/use-tree-list'
import {useUrlCreator} from '@github-ui/code-view-shared/hooks/use-url-creator'
import {WebWorker} from '@github-ui/code-view-shared/utilities/web-worker'
import {
  type FindFileRequest,
  type FindFileResponse,
  findFileWorkerJob,
} from '@github-ui/code-view-shared/worker-jobs/find-file'
import {useCurrentRepository} from '@github-ui/current-repository'
import {getScrollableParent} from '@github-ui/get-scrollable-parent'
import {codeNavSearchPath} from '@github-ui/paths'
import {Link} from '@github-ui/react-core/link'
// eslint-disable-next-line no-restricted-imports
import {ScreenSize, useScreenSize} from '@github-ui/screen-size'
import {useNavigate} from '@github-ui/use-navigate'
import {FocusKeys, scrollIntoView} from '@primer/behaviors'
import {FileDirectoryFillIcon, FileIcon} from '@primer/octicons-react'
import {
  ActionList,
  AnchoredOverlay,
  type BetterSystemStyleObject,
  Box,
  Flash,
  type SxProp,
  useFocusZone,
} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {positions} from 'fzy.js'
import React, {useCallback, useMemo} from 'react'

import {FilesSearchBox, isSearchUrl} from './FilesSearchBox'

const LIST_SIZE = 20

const defaultConfig = {
  excludeDirectories: false,
  excludeSeeAllResults: false,
}

type FileResultsConfigBase = {
  /** If true, directories will be excluded from the search results. */
  excludeDirectories?: boolean
  /** If true, the "See All Results" option will be excluded from the search results. */
  excludeSeeAllResults?: boolean
  /** If true, the results list will be rendered in an `<AnchoredOverlay>` element. */
  enableOverlay?: boolean
  /** Optional placeholder text for the search box. */
  searchPlaceholder?: string
}

type WithNavigation = FileResultsConfigBase & {
  /** If true, search results are rendered in a `<li>` tag instead of an `<a>` tag */
  disableNavigation?: false
  actionText?: never
}

type WithoutNavigation = FileResultsConfigBase & {
  /** If true, search results are rendered in a `<li>` tag instead of an `<a>` tag */
  disableNavigation: true
  /** Custom text for the action button in the search results. Required when disableNavigation is true. */
  actionText: string
}

export type FileResultsConfig = WithNavigation | WithoutNavigation

type FileResultsListProps = {
  actionListSx?: BetterSystemStyleObject
  additionalResults?: string[]
  commitOid: string
  config?: FileResultsConfig
  findFileWorkerPath: string
  getItemUrl?(path: string, isDirectory: boolean, hash: string): string
  onRenderRow?(): void
  onItemSelected?: (path?: string) => void
  searchBoxRef?: React.RefObject<HTMLInputElement>
} & SxProp

export default function FileResultsList({
  actionListSx,
  additionalResults,
  commitOid,
  config = defaultConfig,
  findFileWorkerPath,
  getItemUrl,
  onRenderRow,
  onItemSelected,
  searchBoxRef,
  sx,
}: FileResultsListProps) {
  const {excludeDirectories, excludeSeeAllResults} = config
  const {query, setQuery} = useFileQueryContext()
  const repo = useCurrentRepository()
  const internalInputRef = React.useRef<HTMLInputElement>(null)
  const inputRef = searchBoxRef ?? internalInputRef
  // Mount results component early to start fetching search paths before user starts typing
  // for a more responsive experience.
  const [preloadSearch, setPreloadSearch] = React.useState(false || query.length > 0)
  const [overlayOpen, setOverlayOpen] = React.useState(!!query)
  const {list, directories, loading, error} = useTreeList(commitOid, preloadSearch, !!excludeDirectories)
  const {path} = useFilesPageInfo()
  const {getUrl} = useUrlCreator()
  const {queryText, queryLine} = parseQuery(query)
  const combinedList = useMemo(() => [...list, ...(additionalResults ?? [])].sort(), [additionalResults, list])
  const {matches, clearMatches} = useFilter(combinedList, queryText, findFileWorkerPath, preloadSearch)
  const {sendRepoClickEvent} = useReposAnalytics()
  const navigate = useNavigate()
  const [focusedSearchIndex, setFocusedSearchIndex] = React.useState<number>(0)
  const [listFocusVisible, setListFocusVisible] = React.useState(() => isSearchUrl())
  const allResultsLink = React.useRef<HTMLAnchorElement>(null)
  const textInputContainerRef = React.useRef<HTMLDivElement>(null)
  const overlayId = 'file-results-list'
  const {sendRepoKeyDownEvent} = useReposAnalytics()
  // This is SSR safe because we will wrap calls to FileResultsList with `lazy`
  const {screenSize} = useScreenSize()
  const enableOverlay = config.enableOverlay ?? screenSize >= ScreenSize.large

  const onRowClick = React.useCallback(
    (selectedPath: string) => {
      sendRepoClickEvent('FILE_TREE.SEARCH_RESULT_CLICK')
      onItemSelected?.(selectedPath)
      setOverlayOpen(false)
    },
    [sendRepoClickEvent, onItemSelected],
  )

  const buildUrl = (itemPath: string, isDirectory: boolean, hash: string) => {
    if (getItemUrl) return getItemUrl(itemPath, isDirectory, hash)

    return getUrl({
      path: itemPath,
      action: isDirectory ? 'tree' : 'blob',
      hash,
    })
  }

  const {containerRef: listRef} = useFocusZone(
    {
      bindKeys: FocusKeys.ArrowVertical | FocusKeys.HomeAndEnd,
      focusInStrategy: 'previous',
    },
    [loading, error],
  )

  React.useEffect(() => {
    if (!query) {
      setOverlayOpen(false)
    }
  }, [query])

  React.useEffect(() => {
    if (document.activeElement !== inputRef.current && enableOverlay) {
      setOverlayOpen(false)
    }
  }, [path, inputRef, enableOverlay])

  const displayMatches = matches?.slice(0, LIST_SIZE) || []

  const matchesTruncated = matches && matches.length > displayMatches.length

  const navigationEnabled = !config.disableNavigation

  const handleSearchBoxKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    const {key, shiftKey, metaKey, altKey, ctrlKey} = event
    if (shiftKey || metaKey || altKey) return

    if (key === 'Escape') {
      if (query) {
        sendRepoKeyDownEvent('FILE_TREE.CANCEL_SEARCH')
        setQuery('')
        clearMatches()
      } else if (document.activeElement) {
        // eslint-disable-next-line github/no-blur
        ;(document.activeElement as HTMLInputElement).blur()
      }
    } else if (!query) {
      return
    } else if (key === 'Enter') {
      if (!excludeSeeAllResults && matchesTruncated && focusedSearchIndex === displayMatches.length) {
        if (navigationEnabled) {
          navigate(
            codeNavSearchPath({
              owner: repo.ownerLogin,
              repo: repo.name,
              searchTerm: `path:${queryText}`,
            }),
          )
        }
        onItemSelected?.()
      } else if (displayMatches[focusedSearchIndex]) {
        const selectedPath = displayMatches[focusedSearchIndex]
        if (navigationEnabled) {
          const itemUrl = buildUrl(displayMatches[focusedSearchIndex], false, queryLine ? `L${queryLine}` : '')
          navigate(itemUrl)
        }
        setOverlayOpen(false)
        onItemSelected?.(selectedPath)
      }
    } else if (key === 'ArrowDown' || (ctrlKey && key === 'n')) {
      // Move to the "See all results" link
      if (!excludeSeeAllResults && matchesTruncated && focusedSearchIndex >= displayMatches.length - 1) {
        setFocusedSearchIndex(displayMatches.length)
        if (allResultsLink.current && listRef.current) {
          const container = getScrollableParent(listRef.current)
          scrollIntoView(allResultsLink.current, container as HTMLElement, {behavior: 'instant'})
        }
      } else {
        setFocusedSearchIndex(Math.min(focusedSearchIndex + 1, displayMatches.length - 1))
      }

      event.preventDefault()
      return
    } else if (key === 'ArrowUp' || (ctrlKey && key === 'p')) {
      setFocusedSearchIndex(Math.max(focusedSearchIndex - 1, 0))
      event.preventDefault()
      return
    }
  }

  const inputWidth = textInputContainerRef.current?.getBoundingClientRect().width

  const listContents = (
    <Box
      sx={{
        maxHeight: enableOverlay ? '180px' : '100% !important',
        overflowY: 'auto',
        scrollbarGutter: 'stable',
        maxWidth: '100vw',
        width: enableOverlay ? inputWidth : '100%',
      }}
    >
      {error ? (
        <Flash variant="danger" className="m-3">
          Failed to search
        </Flash>
      ) : (
        <ActionList
          ref={listRef as React.RefObject<HTMLUListElement>}
          sx={{
            overflow: 'auto',
            p: enableOverlay ? 2 : 3,
            width: '100%',
            pr: enableOverlay ? 3 : 0,
            pt: enableOverlay ? 3 : '2px !important',
            ...actionListSx,
          }}
          role="listbox"
        >
          {!loading &&
            displayMatches.map((match, index) => {
              const isDirectory = directories.includes(match)
              const itemUrl = buildUrl(match, isDirectory, queryLine ? `L${queryLine}` : '')
              return (
                <MemoizedFileResultRow
                  active={false}
                  index={index}
                  key={match}
                  focused={listFocusVisible && focusedSearchIndex === index}
                  match={match}
                  onRender={onRenderRow}
                  query={queryText}
                  onClick={onRowClick}
                  isDirectory={isDirectory}
                  to={itemUrl}
                  useOverlay={enableOverlay}
                  listRef={listRef}
                  noAnchor={config.disableNavigation}
                />
              )
            })}
          {displayMatches.length === 0 && (
            <div role="status" className="text-center fgColor-muted">
              No matches found
            </div>
          )}
        </ActionList>
      )}
    </Box>
  )

  return (
    <>
      <Box ref={textInputContainerRef} sx={{...sx}}>
        <FilesSearchBox
          ariaActiveDescendant={
            (enableOverlay || !query) && (!enableOverlay || !overlayOpen)
              ? undefined
              : listFocusVisible && focusedSearchIndex > -1
                ? matchesTruncated && focusedSearchIndex === displayMatches.length
                  ? 'see-all-results-link'
                  : `file-result-${focusedSearchIndex}`
                : undefined
          }
          ariaExpanded={enableOverlay ? overlayOpen : undefined}
          ariaHasPopup={enableOverlay}
          ariaControls={enableOverlay ? overlayId : undefined}
          ref={inputRef}
          loading={loading}
          query={query}
          onKeyDown={handleSearchBoxKeyDown}
          onPreload={() => setPreloadSearch(true)}
          onSearch={newQuery => {
            setQuery(newQuery)
            if (newQuery) {
              setOverlayOpen(true)
            } else {
              clearMatches()
              setOverlayOpen(false)
            }
            setFocusedSearchIndex(0)
          }}
          onBlur={e => {
            if (!listRef.current?.contains(e.relatedTarget)) {
              setOverlayOpen(false)
              setListFocusVisible(false)
            }
          }}
          onFocus={() => {
            if (query) {
              setOverlayOpen(true)
            }
            setListFocusVisible(true)
          }}
          searchPlaceholder={config.searchPlaceholder}
          sx={{minWidth: '160px'}}
        />
      </Box>
      {enableOverlay && displayMatches.length > 0 && (
        <AnchoredOverlay
          anchorRef={textInputContainerRef}
          open={enableOverlay && overlayOpen}
          renderAnchor={null}
          onClose={() => {
            setOverlayOpen(false)
          }}
          focusZoneSettings={{disabled: true}}
          focusTrapSettings={{disabled: true}}
          align="end"
          overlayProps={{id: overlayId, role: 'dialog'}}
        >
          {listContents}
        </AnchoredOverlay>
      )}
      {!enableOverlay && query && listContents}
    </>
  )
}

interface FileResultRowProps {
  active: boolean
  focused?: boolean
  index: number
  match: string
  isDirectory: boolean
  onClick?(path: string): void
  query: string
  to: string
  onRender?(): void
  useOverlay: boolean
  listRef?: React.RefObject<HTMLElement>
  noAnchor?: boolean
}

export const FileResultRow = ({
  active,
  focused,
  index,
  match,
  query,
  to,
  isDirectory,
  onClick,
  onRender,
  useOverlay,
  listRef,
  noAnchor,
}: FileResultRowProps) => {
  const positionsList = positions(query, match)
  onRender?.()

  const ref = React.useRef<HTMLAnchorElement>(null)
  const leadingIcon = isDirectory ? DirectoryIcon : FileResultIcon

  React.useEffect(() => {
    if (focused && ref.current && listRef?.current) {
      const container = getScrollableParent(listRef.current)
      scrollIntoView(ref.current, container as HTMLElement, {behavior: 'instant'})
    }
  }, [focused, listRef])

  let sx = {}
  if (focused) {
    sx = {
      outline: 'none',
      border: '2 solid',
      boxShadow: '0 0 0 2px #0969da',
    }
  }

  const onClickWrapped = useCallback(() => {
    onClick?.(match)
  }, [match, onClick])

  const sharedItemProps = {
    id: `file-result-${index}`,
    active,
    onSelect: onClickWrapped,
    sx: {
      fontWeight: 'normal',
      ':hover': {
        textDecoration: 'none',
      },
      mx: '2px',
      width: 'calc(100% - 4px)',
      ...sx,
    },
    role: 'option' as const,
    'data-focus-visible-added': focused || undefined,
    tabIndex: useOverlay ? -1 : 0,
  }

  const innerContent = (
    <div className="d-flex">
      <div className="d-flex flex-1 flex-column overflow-hidden">
        <HighlightMatch text={match} positionsList={positionsList} sx={{color: 'fg.muted'}} LeadingIcon={leadingIcon} />
      </div>
    </div>
  )

  return noAnchor ? (
    <ActionList.Item {...sharedItemProps} key={match}>
      {innerContent}
    </ActionList.Item>
  ) : (
    <ActionList.Item {...sharedItemProps} ref={ref} as={Link} to={to} key={match}>
      {innerContent}
    </ActionList.Item>
  )
}

const DirectoryIcon = () => (
  <Octicon
    aria-label="Directory"
    icon={FileDirectoryFillIcon}
    sx={{color: 'var(--treeViewItem-leadingVisual-iconColor-rest, var(--color-icon-directory))', mr: 2}}
    size="small"
  />
)

const FileResultIcon = () => <Octicon aria-label="File" icon={FileIcon} className="fgColor-muted mr-2" size="small" />

const MemoizedFileResultRow = React.memo(FileResultRow)

interface HighlightMatchProps extends SxProp {
  text: string
  positionsList: number[]
  offset?: number
  LeadingIcon?: React.ComponentType
}

function HighlightMatch({text, positionsList, sx, LeadingIcon}: HighlightMatchProps) {
  const parts = []
  let lastPosition = 0
  for (const i of positionsList) {
    if (Number(i) !== i || i < lastPosition || i > text.length) {
      continue
    }
    const slice = text.slice(lastPosition, i)
    if (slice) {
      parts.push(allowSlashWrapping(slice))
    }

    lastPosition = i + 1

    parts.push(
      <mark key={i} className="text-bold bgColor-transparent fgColor-default">
        {text[i]}
      </mark>,
    )
  }

  parts.push(allowSlashWrapping(text.slice(lastPosition)))

  return (
    <Box sx={sx}>
      <>
        {LeadingIcon && <LeadingIcon />}
        {parts}
      </>
    </Box>
  )
}

function allowSlashWrapping(text: string): string {
  // Add a zero-width-space after each slash, so that the browser can wrap the text
  return text.replaceAll('/', '/\u200B')
}

function useFilter(list: string[], query: string, workerPath: string, startWorker: boolean) {
  const [matches, setMatches] = React.useState<string[]>()
  const lastQueryRef = React.useRef<string>('')
  const workerRef = React.useRef<WebWorker<FindFileRequest, FindFileResponse>>()
  const {sendStats} = useReposAnalytics()
  const isWorkerWorking = React.useRef(false)

  const createWorker = React.useCallback(() => {
    const worker = new WebWorker(workerPath, findFileWorkerJob)

    worker.onmessage = ({data}: {data: FindFileResponse}) => {
      isWorkerWorking.current = false
      setMatches(data.list)
      lastQueryRef.current = data.query

      if (data.startTime) {
        sendStats('repository.find-file', {
          'find-file-base-count': data.baseCount,
          'find-file-results-count': data.list.length,
          'find-file-duration-ms': performance.now() - data.startTime,
        })
      }
    }

    workerRef.current = worker
  }, [sendStats, workerPath])

  React.useEffect(() => {
    if (!startWorker) return
    createWorker()

    return function destroy() {
      workerRef.current?.terminate()
    }
  }, [createWorker, startWorker])

  React.useEffect(() => {
    if (list.length && query) {
      // If a worker is currently filtering and we get a new query,
      // don't wait for it to finish. Terminate the worker and start a new one.
      if (isWorkerWorking.current) {
        workerRef.current?.terminate()
        createWorker()
      }
      const canFilterPreviousMatches = lastQueryRef.current && query.startsWith(lastQueryRef.current)
      isWorkerWorking.current = true
      workerRef.current?.postMessage({
        baseList: (canFilterPreviousMatches && matches) || list,
        query,
        startTime: performance.now(),
      })
    }
    // We don't want to re-run this when `matches` change because we never have to filter again in that case
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [list, query, createWorker])

  return {matches, clearMatches: () => setMatches(undefined)}
}

function parseQuery(query: string) {
  query = query.replaceAll(' ', '')
  const colonIndex = query.indexOf(':')
  if (colonIndex >= 0) {
    return {
      queryText: query.substring(0, colonIndex),
      queryLine: parseInt(query.substring(colonIndex + 1), 10),
    }
  }
  return {queryText: query, queryLine: undefined}
}
