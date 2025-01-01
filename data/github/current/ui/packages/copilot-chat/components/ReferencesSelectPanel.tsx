import {debounce} from '@github/mini-throttle'
import {useQuery} from '@github-ui/react-query'
import {CodeSquareIcon, FileDiffIcon, FileDirectoryFillIcon, FileIcon, PaperclipIcon} from '@primer/octicons-react'
import {AnchoredOverlay, type AnchoredOverlayProps, Box} from '@primer/react'
import {ActionList} from '@primer/react'
import {SelectPanel} from '@primer/react/experimental'
import {type RefObject, useCallback, useEffect, useRef, useState} from 'react'
import {flushSync} from 'react-dom'

import {group as groupArray} from '../utils/array'
import type {CopilotAutocompleteManager} from '../utils/copilot-autocompletions'
import {fileDiffRefName, isRepository, referenceID} from '../utils/copilot-chat-helpers'
import {useFilter} from '../utils/copilot-chat-hooks'
import type {CopilotChatState} from '../utils/copilot-chat-reducer'
import type {
  CopilotChatReference,
  CopilotChatRepo,
  FileReference,
  FolderReference,
  SuggestionSymbolReference,
} from '../utils/copilot-chat-types'
import {useChatAutocomplete} from '../utils/CopilotChatAutocompleteContext'
import {useChatState, useChatStateLens} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import styles from './ReferencesSelectPanel.module.css'
import {RepoSelectPanel} from './RepoSelectPanel'

const headerText = 'Select files, folders, and symbols'
const subheaderText = (repo: string) =>
  `Choose items from ${repo} to chat about. Use fewer references for more accurate responses.`
const filterPlaceholder = 'Search'

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
        description="Choose a repository to browse for files and symbols."
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

interface ReferencesSelectPanelProps {
  renderAnchor?: AnchoredOverlayProps['renderAnchor']
  anchorRef?: RefObject<HTMLButtonElement>
  open: boolean
  onOpenChange: (val: boolean) => void
  submitReturnFocusRef: RefObject<HTMLElement>
  cancelReturnFocusRef: RefObject<HTMLElement>
  /** Repository from which to select files, folders, and symbols. */
  sourceRepository: CopilotChatRepo
}

const ReferencesSelectPanel = ({
  renderAnchor,
  anchorRef,
  open,
  onOpenChange,
  submitReturnFocusRef,
  cancelReturnFocusRef,
  sourceRepository,
}: ReferencesSelectPanelProps) => {
  const {findFileWorkerPath} = useChatState()

  const [query, setQuery] = useState('')
  const debouncedSetQuery = useRef(debounce(setQuery, 250))

  useEffect(() => {
    if (!open) setQuery('')
  }, [open])

  const {initialLoading, filterLoading, selected, unselected, toggleSelection} = useReferencesData(
    open,
    query,
    sourceRepository,
    findFileWorkerPath,
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
        title={headerText}
        description={subheaderText(nwo)}
        onCancel={() => {
          flushSync(() => onOpenChange(false))
          submitReturnFocusRef.current?.focus()
        }}
        onSubmit={() => {
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
            <SelectPanel.Loading>Fetching files, folders, and symbols&hellip;</SelectPanel.Loading>
          ) : totalResults === 0 && !filterLoading ? (
            <SelectPanel.Message variant="empty" title="No files or symbols found">
              Try a different search term
            </SelectPanel.Message>
          ) : (
            <>
              {selected.map(item => (
                <ReferenceListItem key={item.id} item={item} selected toggleSelection={toggleSelection} />
              ))}
              {selected.length > 0 && unselected.length > 0 && <ActionList.Divider />}
              {unselected.map(item => (
                <ReferenceListItem key={item.id} item={item} selected={false} toggleSelection={toggleSelection} />
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

const referenceListItemId = (item: Item) => `reference-list-item-${item.id}`

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
          document.getElementById(referenceListItemId(item))?.focus()
        })
      }}
      selected={selected}
      aria-checked={selected}
      id={referenceListItemId(item)}
      sx={{
        mx: 2,
        '&[data-is-active-descendant="activated-directly"]': {
          backgroundColor: 'transparent',
          outline: '2px solid var(--focus-outlineColor, var(--color-accent-emphasis))',
          outlineOffset: '-2px',
        },
      }}
    >
      <ActionList.LeadingVisual>{item.renderLeadingVisual()}</ActionList.LeadingVisual>
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
  id: string
  key: string
  renderLeadingVisual: () => JSX.Element
  text: string
}

const DISPLAYED_MATCHES_LIMIT = 7

/**
 * useReferencesData handles managing the user's selection, and
 * applying that selection to the chat state.
 */
function useReferencesData(open: boolean, query: string, repo: CopilotChatRepo | null, workerPath: string) {
  const state = useChatState()
  const manager = useChatManager()
  const autocomplete = useChatAutocomplete()
  const queriedItemsResult = useQueriedItems(query, repo, workerPath, open, state.currentReferences)

  const selectedIDs = state.currentReferences.map(ref => referenceID(ref)).filter(id => id !== undefined)

  const {selected = [], unselected = []} = groupArray(queriedItemsResult.items, item =>
    selectedIDs.includes(item.id) ? 'selected' : 'unselected',
  )

  const toggleSelection = useCallback(
    async (item: Item) => {
      const reference = state.currentReferences.find(ref => item.id === referenceID(ref))

      if (reference) {
        manager.removeReference(reference)
      } else {
        await addItemReference(item, state, autocomplete)
      }
    },
    [autocomplete, manager, state],
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

function uniqueMerge<T>(a: Iterable<T>, b: Iterable<T>) {
  return Array.from(new Set([...a, ...b]))
}

/**
 * useQueriesItems handles fetching an appropriate list of items based on the user's query
 */
function useQueriedItems(
  query: string,
  repo: CopilotChatRepo | null,
  workerPath: string,
  open: boolean,
  currentReferences: CopilotChatReference[],
): QueriedItemsResult {
  const autocomplete = useChatAutocomplete()

  const currentFilesByPath = new Map(
    currentReferences
      .filter((r): r is FileReference => r.type === 'file' && r.repoID === repo?.id)
      .map(r => [r.path, r]),
  )
  const currentFoldersByPath = new Map(
    currentReferences
      .filter((r): r is FolderReference => r.type === 'folder' && r.repoID === repo?.id)
      .map(r => [r.path, r]),
  )
  const currentSymbolsByName = new Map(
    currentReferences
      .filter(
        (r): r is SuggestionSymbolReference =>
          r.type === 'symbol' &&
          r.kind === 'suggestionSymbol' &&
          (r.suggestionDefinitions?.some(def => def.repoID === repo?.id) ?? false),
      )
      .map(r => [r.name, r]),
  )

  const {isLoading: autocompleteLoading, data} = useQuery({
    // eslint-disable-next-line @tanstack/query/exhaustive-deps
    queryKey: ['copilot-chat', 'files-autocomplete', repo?.ownerLogin, repo?.name, query],
    queryFn: async () => {
      if (!repo) return null

      await autocomplete.fetchAutocompleteSuggestions(repo, query)

      return {
        filePaths: uniqueMerge(
          Array.from(autocomplete.fileSuggestions.values()).map($result => $result.path),
          currentFilesByPath.keys(),
        ),
        folderPaths: uniqueMerge(
          Array.from(autocomplete.folderSuggestions.values()).map($result => $result.path),
          currentFoldersByPath.keys(),
        ),
        symbolNames: uniqueMerge(
          Array.from(autocomplete.symbolSuggestions.values()).map($result => $result.name),
          currentSymbolsByName.keys(),
        ),
      }
    },
    enabled: open,
  })

  const [matchingFiles, filesSearching] = useFilter(data?.filePaths ?? null, query, workerPath)
  const [matchingFolders, foldersSearching] = useFilter(data?.folderPaths ?? null, query, workerPath)
  const [matchingSymbols, symbolsSearching] = useFilter(data?.symbolNames ?? null, query, workerPath)

  const fileItems: Item[] = matchingFiles
    .slice(0, DISPLAYED_MATCHES_LIMIT)
    .map(e => autocomplete.fileSuggestions.get(e) ?? currentFilesByPath.get(e))
    .filter((item): item is FileReference => !!item)
    .map(item => referenceToItem(item))
    .filter((item): item is Item => !!item)

  const folderItems: Item[] = matchingFolders
    .slice(0, DISPLAYED_MATCHES_LIMIT)
    .map(e => autocomplete.folderSuggestions.get(e) ?? currentFoldersByPath.get(e))
    .filter((item): item is FolderReference => !!item)
    .map(item => referenceToItem(item))
    .filter((item): item is Item => !!item)

  const symbolItems: Item[] = matchingSymbols
    .slice(0, DISPLAYED_MATCHES_LIMIT)
    .map(e => autocomplete.symbolSuggestions.get(e) ?? currentSymbolsByName.get(e))
    .filter((item): item is SuggestionSymbolReference => !!item)
    .map(item => referenceToItem(item))
    .filter((item): item is Item => !!item)

  const items = [...fileItems, ...folderItems, ...symbolItems]

  const initialLoading = autocompleteLoading && !query
  const filterLoading =
    !initialLoading && (autocompleteLoading || filesSearching || foldersSearching || symbolsSearching)

  return {items, filterLoading, initialLoading}
}

function referenceToItem(reference: CopilotChatReference): Item | undefined {
  const refID = referenceID(reference)

  switch (reference.type) {
    case 'symbol':
      return {
        id: refID,
        key: refID,
        renderLeadingVisual: () => <CodeSquareIcon />,
        text: reference.name,
      }
    case 'file':
      return {
        id: refID,
        key: refID,
        renderLeadingVisual: () => <FileIcon />,
        text: reference.path,
      }
    case 'folder':
      return {
        id: refID,
        key: refID,
        renderLeadingVisual: () => <FileDirectoryFillIcon />,
        text: reference.path,
      }
    case 'file-diff':
      return {
        id: refID,
        key: refID,
        renderLeadingVisual: () => <FileDiffIcon />,
        text: fileDiffRefName(reference),
      }
  }
}

async function addItemReference(selection: Item, state: CopilotChatState, autocomplete: CopilotAutocompleteManager) {
  if (selection.id && typeof selection.id === 'string' && selection.text) {
    const symbolSelection = autocomplete.symbolSuggestions.get(selection.text)
    const fileSelection = autocomplete.fileSuggestions.get(selection.text)
    const folderSelection = autocomplete.folderSuggestions.get(selection.text)

    if (symbolSelection) {
      await autocomplete.addToReferences(symbolSelection, state)
    }
    if (fileSelection) {
      await autocomplete.addToReferences(fileSelection, state)
    }
    if (folderSelection) {
      await autocomplete.addToReferences(folderSelection, state)
    }
  }
}
