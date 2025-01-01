import {debounce} from '@github/mini-throttle'
import {CodeSquareIcon, FileDirectoryFillIcon, FileIcon, PaperclipIcon} from '@primer/octicons-react'
import {AnchoredOverlay, type AnchoredOverlayProps, Box} from '@primer/react'
import {ActionList} from '@primer/react'
import {SelectPanel} from '@primer/react/experimental'
import {type RefObject, useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {flushSync} from 'react-dom'

import {useFilterQuery} from '../hooks/use-filter-query'
import {useRepositoryFilesQuery} from '../hooks/use-repository-files-query'
import {useRepositorySymbolsQuery} from '../hooks/use-repository-symbols-query'
import {group as groupArray} from '../utils/array'
import {
  getSymbolName,
  isRepository,
  makeFileReference,
  makeFolderReference,
  makeSymbolReference,
  referenceID,
} from '../utils/copilot-chat-helpers'
import type {CopilotChatRepo} from '../utils/copilot-chat-types'
import {useChatState, useChatStateLens} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import styles from './ReferencesSelectPanel.module.css'
import {RepoSelectPanel} from './RepoSelectPanel'

const filterPlaceholder = 'Search'

// Helper functions to generate dynamic strings based on option flags
const getHeaderText = (supportedReferenceTypes: SupportedReferenceType[]) => {
  const includeFiles = supportedReferenceTypes.includes('files')
  const includeFolders = supportedReferenceTypes.includes('folders')
  const includeSymbols = supportedReferenceTypes.includes('symbols')

  if (includeFiles && includeFolders && includeSymbols) return 'Select files, folders, and symbols'
  if (includeFiles && includeFolders) return 'Select files and folders'
  if (includeFiles && includeSymbols) return 'Select files and symbols'
  if (includeFolders && includeSymbols) return 'Select folders and symbols'
  if (includeFiles) return 'Select files'
  if (includeFolders) return 'Select folders'
  if (includeSymbols) return 'Select symbols'
  return 'Select references'
}

const getSubheaderText = (repo: string, supportedReferenceTypes: SupportedReferenceType[]) => {
  const includeFiles = supportedReferenceTypes.includes('files')
  const includeFolders = supportedReferenceTypes.includes('folders')
  const includeSymbols = supportedReferenceTypes.includes('symbols')

  let itemsText = 'references'
  if (includeFiles && includeFolders && includeSymbols) itemsText = 'files, folders, and symbols'
  else if (includeFiles && includeFolders) itemsText = 'files and folders'
  else if (includeFiles && includeSymbols) itemsText = 'files and symbols'
  else if (includeFolders && includeSymbols) itemsText = 'folders and symbols'
  else if (includeFiles) itemsText = 'files'
  else if (includeFolders) itemsText = 'folders'
  else if (includeSymbols) itemsText = 'symbols'

  return `Choose ${itemsText} from ${repo} to chat about. Use fewer references for more accurate responses.`
}

const getLoadingText = (supportedReferenceTypes: SupportedReferenceType[]) => {
  const includeFiles = supportedReferenceTypes.includes('files')
  const includeFolders = supportedReferenceTypes.includes('folders')
  const includeSymbols = supportedReferenceTypes.includes('symbols')

  if (includeFiles && includeFolders && includeSymbols) return 'Fetching files, folders, and symbols…'
  if (includeFiles && includeFolders) return 'Fetching files and folders…'
  if (includeFiles && includeSymbols) return 'Fetching files and symbols…'
  if (includeFolders && includeSymbols) return 'Fetching folders and symbols…'
  if (includeFiles) return 'Fetching files…'
  if (includeFolders) return 'Fetching folders…'
  if (includeSymbols) return 'Fetching symbols…'
  return 'Fetching references…'
}

/**
 * Label text for the ActionList.Item
 */
export const getLabelText = (supportedReferenceTypes: SupportedReferenceType[]) => {
  const includeFiles = supportedReferenceTypes.includes('files')
  const includeFolders = supportedReferenceTypes.includes('folders')
  const includeSymbols = supportedReferenceTypes.includes('symbols')

  let itemsText = 'References'
  if (includeFiles && includeFolders && includeSymbols) itemsText = 'Files, folders, and symbols'
  else if (includeFiles && includeFolders) itemsText = 'Files and folders'
  else if (includeFiles && includeSymbols) itemsText = 'Files and symbols'
  else if (includeFolders && includeSymbols) itemsText = 'Folders and symbols'
  else if (includeFiles) itemsText = 'Files'
  else if (includeFolders) itemsText = 'Folders'
  else if (includeSymbols) itemsText = 'Symbols'
  return itemsText
}

const getRepoSelectionDescription = (supportedReferenceTypes: SupportedReferenceType[]) => {
  const includeFiles = supportedReferenceTypes.includes('files')
  const includeFolders = supportedReferenceTypes.includes('folders')
  const includeSymbols = supportedReferenceTypes.includes('symbols')

  if (includeFiles && includeFolders && includeSymbols)
    return 'Choose a repository to browse for files, folders, and symbols.'
  if (includeFiles && includeFolders) return 'Choose a repository to browse for files and folders.'
  if (includeFiles && includeSymbols) return 'Choose a repository to browse for files and symbols.'
  if (includeFolders && includeSymbols) return 'Choose a repository to browse for folders and symbols.'
  if (includeFiles) return 'Choose a repository to browse for files.'
  if (includeFolders) return 'Choose a repository to browse for folders.'
  if (includeSymbols) return 'Choose a repository to browse for symbols.'
  return 'Choose a repository to browse for references.'
}

const getEmptyStateTitle = (supportedReferenceTypes: SupportedReferenceType[]): string => {
  const includeFiles = supportedReferenceTypes.includes('files')
  const includeFolders = supportedReferenceTypes.includes('folders')
  const includeSymbols = supportedReferenceTypes.includes('symbols')

  if (includeFiles && includeFolders && includeSymbols) return 'No files, folders, or symbols found'
  if (includeFiles && includeFolders) return 'No files or folders found'
  if (includeFiles && includeSymbols) return 'No files or symbols found'
  if (includeFolders && includeSymbols) return 'No folders or symbols found'
  if (includeFiles) return 'No files found'
  if (includeFolders) return 'No folders found'
  if (includeSymbols) return 'No symbols found'
  return 'No references found'
}

type TopicReferencesSelectPanelProps = Omit<ReferencesSelectPanelProps, 'sourceRepository'>

/** Uses the currently selected topic repository as the source repo for the references. */
export const TopicReferencesSelectPanel = ({open, onOpenChange, ...props}: TopicReferencesSelectPanelProps) => {
  const {currentTopic} = useChatState()

  if (!isRepository(currentTopic)) {
    return <ChooseRepositoryInstruction open={open} setOpen={onOpenChange} />
  }

  return <ReferencesSelectPanel {...props} open={open} onOpenChange={onOpenChange} sourceRepository={currentTopic} />
}

type MultistepReferencesSelectPanelProps = TopicReferencesSelectPanelProps

/** First shows a repo select panel, then selects references from that repo. */
export const MultistepReferencesSelectPanel = ({
  open,
  onOpenChange,
  cancelReturnFocusRef,
  submitReturnFocusRef,
  ...props
}: MultistepReferencesSelectPanelProps) => {
  const manager = useChatManager()
  const [repo, setRepo] = useState<CopilotChatRepo>()

  useEffect(() => setRepo(undefined), [open])

  const references = useChatStateLens(s => s.currentReferences)
  const repoReferenceIds = new Set(references.filter(r => r.type === 'repository').map(r => r.id))

  const [reposError, setReposError] = useState<string>()

  const selectingRepo = useRef(false)
  const onSelectRepo = async (repoId: number) => {
    setReposError(undefined)

    selectingRepo.current = true
    const repoResponse = await manager.service.fetchRepo(repoId)

    if (!repoResponse.ok) {
      setReposError('Error: failed to load repository details. Please try again.')
    } else {
      setRepo(repoResponse.payload)
    }

    selectingRepo.current = false
  }

  const description = getRepoSelectionDescription(props.supportedReferenceTypes ?? defaultSupportedReferenceTypes)
  if (!repo)
    return (
      <RepoSelectPanel
        selectionVariant="instant"
        open={open}
        onOpenChange={newOpen => {
          // Ignore while loading repo data in order to avoid flash
          if (!selectingRepo.current) onOpenChange(newOpen)
        }}
        selectedRepoIds={new Set()}
        onSelectRepo={onSelectRepo}
        cancelReturnFocusRef={cancelReturnFocusRef}
        submitReturnFocusRef={submitReturnFocusRef}
        description={description}
        featuredRepoIds={repoReferenceIds}
        error={reposError}
      />
    )

  return (
    <ReferencesSelectPanel
      {...props}
      open={open}
      onOpenChange={onOpenChange}
      sourceRepository={repo}
      cancelReturnFocusRef={cancelReturnFocusRef}
      submitReturnFocusRef={submitReturnFocusRef}
    />
  )
}

export type SupportedReferenceType = 'files' | 'folders' | 'symbols'

const defaultSupportedReferenceTypes: SupportedReferenceType[] = ['files', 'folders', 'symbols']

interface ReferencesSelectPanelProps {
  renderAnchor?: AnchoredOverlayProps['renderAnchor']
  anchorRef?: RefObject<HTMLButtonElement>
  open: boolean
  onOpenChange: (val: boolean) => void
  submitReturnFocusRef: RefObject<HTMLElement>
  cancelReturnFocusRef: RefObject<HTMLElement>
  /** Repository from which to select references. */
  sourceRepository: CopilotChatRepo
  supportedReferenceTypes?: SupportedReferenceType[]
}

const ReferencesSelectPanel = ({
  renderAnchor,
  anchorRef,
  open,
  onOpenChange,
  submitReturnFocusRef,
  cancelReturnFocusRef,
  sourceRepository,
  supportedReferenceTypes = defaultSupportedReferenceTypes,
}: ReferencesSelectPanelProps) => {
  const [query, setQuery] = useState('')
  const debouncedSetQuery = useRef(debounce(setQuery, 250))

  useEffect(() => {
    if (!open) setQuery('')
  }, [open])

  const {initialLoading, filterLoading, selected, unselected, toggleSelection} = useReferencesData(
    open,
    query,
    sourceRepository,
    supportedReferenceTypes,
  )

  const totalResults = selected.length + unselected.length

  const nwo = `${sourceRepository.ownerLogin}/${sourceRepository.name}`

  return (
    <Box
      sx={{
        flexGrow: '0 !important',
      }}
    >
      {renderAnchor?.({})}
      {/* eslint-disable-next-line primer-react/no-system-props */}
      <SelectPanel
        anchorRef={anchorRef}
        title={getHeaderText(supportedReferenceTypes)}
        description={getSubheaderText(nwo, supportedReferenceTypes)}
        onCancel={() => {
          // eslint-disable-next-line @eslint-react/dom/no-flush-sync
          flushSync(() => onOpenChange(false))
          submitReturnFocusRef.current?.focus()
        }}
        onSubmit={() => {
          // eslint-disable-next-line @eslint-react/dom/no-flush-sync
          flushSync(() => onOpenChange(false))
          cancelReturnFocusRef.current?.focus()
        }}
        open={open}
        selectionVariant="multiple"
        variant="modal"
        width="large"
        maxHeight="xlarge"
      >
        <SelectPanel.Header>
          <SelectPanel.SearchInput
            loading={filterLoading}
            onChange={e => debouncedSetQuery.current(e.target.value)}
            placeholder={filterPlaceholder}
            aria-label={filterPlaceholder}
          />
        </SelectPanel.Header>
        <ActionList sx={{minHeight: 340}}>
          {initialLoading ? (
            <SelectPanel.Loading>{getLoadingText(supportedReferenceTypes)}</SelectPanel.Loading>
          ) : totalResults === 0 && !filterLoading ? (
            <SelectPanel.Message variant="empty" title={getEmptyStateTitle(supportedReferenceTypes)}>
              Try a different search term
            </SelectPanel.Message>
          ) : (
            <>
              {selected.map(item => (
                <ReferenceListItem key={itemId(item)} item={item} selected toggleSelection={toggleSelection} />
              ))}
              {selected.length > 0 && unselected.length > 0 && <ActionList.Divider />}
              {unselected.map(item => (
                <ReferenceListItem key={itemId(item)} item={item} selected={false} toggleSelection={toggleSelection} />
              ))}
            </>
          )}
        </ActionList>
      </SelectPanel>
    </Box>
  )
}

function ChooseRepositoryInstruction({
  open,
  setOpen,
  renderAnchor,
}: {
  open: boolean
  setOpen: (v: boolean) => void
  renderAnchor?: AnchoredOverlayProps['renderAnchor']
}) {
  return (
    <AnchoredOverlay
      open={open}
      onOpen={() => setOpen(true)}
      onClose={() => setOpen(false)}
      renderAnchor={p => renderAnchor?.(p) ?? <></>}
    >
      <div className={styles.chooseRepoInstructionPanel}>
        <PaperclipIcon />
        <h3 className={styles.chooseRepoTitle}>Attach a repository first</h3>
        <p className={styles.chooseRepoSubtitle}>
          To pick attachments, attach a repository where the files are stored.
        </p>
      </div>
    </AnchoredOverlay>
  )
}

const itemId = (item: Item) => `${item.type}#${item.text}`

function ReferenceListItem({
  toggleSelection,
  selected,
  item,
}: {
  toggleSelection: (item: Item) => void
  selected: boolean
  item: Item
}) {
  return (
    <ActionList.Item
      onSelect={() => {
        toggleSelection(item)
        // this item is going to get moved into or out of the selected group on screen, and the re-render will cause it to lose focus so we have to restore it
        setTimeout(() => {
          document.getElementById(itemId(item))?.focus()
        })
      }}
      selected={selected}
      aria-checked={selected}
      id={itemId(item)}
      sx={{
        mx: 2,
        '&[data-is-active-descendant="activated-directly"]': {
          backgroundColor: 'transparent',
          outline: '2px solid var(--focus-outlineColor, var(--color-accent-emphasis))',
          outlineOffset: '-2px',
        },
      }}
    >
      <ActionList.LeadingVisual>
        {item.type === 'symbol' ? (
          <CodeSquareIcon />
        ) : item.type === 'folder' ? (
          <FileDirectoryFillIcon />
        ) : (
          <FileIcon />
        )}
      </ActionList.LeadingVisual>
      <Box
        sx={{
          overflow: 'hidden',
          whiteSpace: 'nowrap',
          textOverflow: 'ellipsis',
        }}
      >
        {item.text}
      </Box>
    </ActionList.Item>
  )
}

interface Item {
  type: 'file' | 'folder' | 'symbol'
  text: string
}

const DISPLAYED_MATCHES_LIMIT = 7

/**
 * useReferencesData handles managing the user's selection, and
 * applying that selection to the chat state.
 */
function useReferencesData(
  open: boolean,
  query: string,
  repo: CopilotChatRepo | null,
  supportedReferenceTypes = defaultSupportedReferenceTypes,
) {
  const state = useChatState()
  const manager = useChatManager()
  const queriedItemsResult = useQueriedItems(query, repo, open, supportedReferenceTypes)
  const includeSymbols = supportedReferenceTypes.includes('symbols')

  // setting the repo to null will skip fetching symbols
  // we need a separate symbols query here in addition to the one in useQueriedItems
  // because we need the full list.
  const symbols = useRepositorySymbolsQuery(open && includeSymbols ? repo : null, query).data
  const [selectedFiles, selectedFolders, selectedSymbols] = useMemo(() => {
    const selectedFilesSet = new Set<string>()
    const selectedFoldersSet = new Set<string>()
    const selectedSymbolsSet = new Set<string>()

    for (const reference of state.currentReferences) {
      if (reference.type === 'file' && reference.repoOwner === repo?.ownerLogin && reference.repoName === repo?.name) {
        selectedFilesSet.add(reference.path)
      } else if (
        reference.type === 'folder' &&
        reference.repoOwner === repo?.ownerLogin &&
        reference.repoName === repo?.name
      ) {
        selectedFoldersSet.add(reference.path)
      } else if (
        reference.type === 'symbol' &&
        reference.kind === 'suggestionSymbol' &&
        reference.suggestionDefinitions?.some(def => def.repoOwner === repo?.ownerLogin && def.repoName === repo?.name)
      ) {
        selectedSymbolsSet.add(reference.name)
      }
    }

    return [selectedFilesSet, selectedFoldersSet, selectedSymbolsSet]
  }, [state.currentReferences, repo?.ownerLogin, repo?.name])

  const {selected = [], unselected = []} = groupArray(queriedItemsResult.items, item => {
    switch (item.type) {
      case 'file':
        return selectedFiles.has(item.text) ? 'selected' : 'unselected'
      case 'folder':
        return selectedFolders.has(item.text) ? 'selected' : 'unselected'
      case 'symbol':
        return selectedSymbols.has(item.text) ? 'selected' : 'unselected'
    }
  })

  const toggleSelection = useCallback(
    (item: Item) => {
      if (!repo) return

      let reference
      switch (item.type) {
        case 'file':
          reference = makeFileReference(item.text, repo)
          break
        case 'folder':
          reference = makeFolderReference(item.text, repo)
          break
        case 'symbol':
          {
            const symbolSelection = symbols?.find(s => getSymbolName(s) === item.text)
            if (!symbolSelection) return
            reference = makeSymbolReference(symbolSelection, repo)
          }
          break
      }

      const id = referenceID(reference)
      const currentReference = state.currentReferences.find(ref => id === referenceID(ref))

      if (currentReference) {
        manager.removeReference(currentReference)
      } else {
        manager.addReference(reference, 'references-menu')
      }
    },
    [manager, repo, state.currentReferences, symbols],
  )

  return {
    ...queriedItemsResult,
    selected,
    unselected,
    toggleSelection,
  }
}

interface QueriedItemsResult {
  items: Item[]
  filterLoading: boolean
  initialLoading: boolean
}

/**
 * useQueriesItems handles fetching an appropriate list of items based on the user's query
 */
function useQueriedItems(
  query: string,
  repo: CopilotChatRepo | null,
  open: boolean,
  supportedReferenceTypes: SupportedReferenceType[] = defaultSupportedReferenceTypes,
): QueriedItemsResult {
  const includeFolders = supportedReferenceTypes.includes('folders')
  const includeSymbols = supportedReferenceTypes.includes('symbols')
  const includeFiles = supportedReferenceTypes.includes('files')

  const queryRepo = open ? repo : null

  const filesAndFoldersQuery = useRepositoryFilesQuery(queryRepo, includeFolders)

  const filteredPathsQuery = useFilterQuery(filesAndFoldersQuery.data?.paths ?? null, query)
  const filteredDirectoriesQuery = useFilterQuery(filesAndFoldersQuery.data?.directories ?? null, query)

  // passing a null repo to the symbols query will skip fetching symbols
  const symbolsQuery = useRepositorySymbolsQuery(includeSymbols ? queryRepo : null, query)

  const symbolNames = symbolsQuery.data?.map(s => getSymbolName(s)) ?? null

  const filteredSymbolsQuery = useFilterQuery(symbolNames, query)

  const fileItems: Item[] = includeFiles
    ? filteredPathsQuery.data?.slice(0, DISPLAYED_MATCHES_LIMIT).map(path => ({type: 'file', text: path})) ?? []
    : []
  const folderItems: Item[] = includeFolders
    ? filteredDirectoriesQuery.data?.slice(0, DISPLAYED_MATCHES_LIMIT).map(path => ({type: 'folder', text: path})) ?? []
    : []
  const symbolItems: Item[] =
    filteredSymbolsQuery.data?.slice(0, DISPLAYED_MATCHES_LIMIT).map(name => ({type: 'symbol', text: name})) ?? []

  const items = [...fileItems, ...folderItems, ...symbolItems]

  const initialLoading =
    filteredPathsQuery.data === null && filteredDirectoriesQuery.data === null && symbolsQuery.data === null

  const filterLoading =
    filesAndFoldersQuery.isFetching ||
    filteredPathsQuery.isFetching ||
    filteredDirectoriesQuery.isFetching ||
    symbolsQuery.isFetching ||
    filteredSymbolsQuery.isFetching

  return {items, filterLoading, initialLoading}
}
