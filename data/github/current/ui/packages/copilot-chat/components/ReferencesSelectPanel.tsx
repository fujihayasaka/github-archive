import {debounce} from '@github/mini-throttle'
import {CodeSquareIcon, FileDiffIcon, FileIcon, PaperclipIcon} from '@primer/octicons-react'
import {AnchoredOverlay, type AnchoredOverlayProps, Box, IconButton, useRefObjectAsForwardedRef} from '@primer/react'
import {ActionList} from '@primer/react'
import {SelectPanel} from '@primer/react/experimental'
import {useQuery} from '@tanstack/react-query'
import {forwardRef, type RefObject, useCallback, useEffect, useRef, useState} from 'react'
import {flushSync} from 'react-dom'

import type {CopilotAutocompleteManager} from '../utils/copilot-autocompletions'
import {fileDiffRefName, isRepository, referenceID} from '../utils/copilot-chat-helpers'
import {useFilter, useSidePanelPositionStyles} from '../utils/copilot-chat-hooks'
import type {CopilotChatState} from '../utils/copilot-chat-reducer'
import type {
  CopilotChatReference,
  CopilotChatRepo,
  FileReference,
  SuggestionSymbolReference,
} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {copilotLocalStorage} from '../utils/copilot-local-storage'
import {useChatAutocomplete} from '../utils/CopilotChatAutocompleteContext'
import {useChatState} from '../utils/CopilotChatContext'
import styles from './ReferencesSelectPanel.module.css'

const headerText = 'Attach files and symbols'
const subheaderText =
  'Choose which files and symbols you want to chat about. Use fewer references for more accurate responses.'
const filterPlaceholder = 'Search files and symbols'

export const ReferencesSelectButton = forwardRef<
  HTMLButtonElement,
  {panelWidth?: number; inputRef: RefObject<HTMLTextAreaElement>}
>(function ReferencesSelectButton({panelWidth, inputRef}, forwardedRef) {
  const [open, setOpen] = useState(false)
  const anchorRef = useRef<HTMLButtonElement>(null)
  useRefObjectAsForwardedRef(forwardedRef, anchorRef)

  return (
    <ReferencesSelectPanel
      panelWidth={panelWidth}
      open={open}
      onOpenChange={setOpen}
      anchorRef={anchorRef}
      cancelReturnFocusRef={anchorRef}
      submitReturnFocusRef={inputRef}
      renderAnchor={({...anchorProps}) => (
        <ReferenceIconButton ref={anchorRef} open={open} setOpen={setOpen} {...anchorProps} />
      )}
    />
  )
})

const ReferenceIconButton = forwardRef<HTMLButtonElement, {open: boolean; setOpen: (v: boolean) => void}>(
  function ReferenceIconButton({open, setOpen, ...buttonProps}, ref) {
    return (
      <IconButton
        ref={ref}
        aria-expanded={open ? true : undefined}
        aria-haspopup
        aria-label="Attach files or symbols"
        aria-labelledby={undefined}
        onClick={() => setOpen(!open)}
        icon={PaperclipIcon}
        variant="invisible"
        sx={{flexShrink: 0}}
        {...buttonProps}
      />
    )
  },
)

interface ReferencesSelectPanelProps {
  panelWidth?: number
  renderAnchor?: AnchoredOverlayProps['renderAnchor']
  anchorRef?: RefObject<HTMLButtonElement>
  open: boolean
  onOpenChange: (val: boolean) => void
  submitReturnFocusRef: RefObject<HTMLElement>
  cancelReturnFocusRef: RefObject<HTMLElement>
}

export const ReferencesSelectPanel = ({
  panelWidth,
  renderAnchor,
  anchorRef,
  open,
  onOpenChange,
  submitReturnFocusRef,
  cancelReturnFocusRef,
}: ReferencesSelectPanelProps) => {
  const {currentTopic, mode, findFileWorkerPath} = useChatState()
  const positionStyles = useSidePanelPositionStyles(open)
  const isImmersiveV1 = mode === 'immersive' && copilotFeatureFlags.copilotImmersiveV1

  const [query, setQuery] = useState('')
  const debouncedSetQuery = useRef(debounce(setQuery, 250))

  useEffect(() => {
    if (!open) setQuery('')
  }, [open])

  const {initialLoading, filterLoading, selected, items, groups, onSelectedChange} = useReferencesData(
    open,
    query,
    isRepository(currentTopic) ? currentTopic : null,
    findFileWorkerPath,
  )

  const persistentPanelStyles =
    mode === 'assistive'
      ? {
          position: 'fixed',
          bottom: 0,
          right: `${panelWidth || copilotLocalStorage.DEFAULT_PANEL_WIDTH}px`,
          left: 'auto !important',
          top: 'auto !important',
          maxWidth: '100vw',
          width: 480,
          minHeight: 600,
          ...positionStyles,
        }
      : {}

  if (!isRepository(currentTopic)) {
    return <ChooseRepositoryInstruction open={open} setOpen={onOpenChange} />
  }

  const isSelected = (item: Item) => !!selected.find(selectedItem => selectedItem.id === item.id)

  return (
    <Box
      sx={{
        flexGrow: '0 !important',
        '> dialog': persistentPanelStyles,
      }}
    >
      {renderAnchor?.({})}
      {/* eslint-disable-next-line primer-react/no-system-props */}
      <SelectPanel
        anchorRef={anchorRef}
        title={headerText}
        description={subheaderText}
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
        variant={isImmersiveV1 ? 'modal' : undefined}
        width={isImmersiveV1 ? 'large' : undefined}
        maxHeight={isImmersiveV1 ? 'xlarge' : undefined}
      >
        <SelectPanel.Header>
          <SelectPanel.SearchInput
            loading={filterLoading}
            onChange={e => debouncedSetQuery.current(e.target.value)}
            placeholder={filterPlaceholder}
          />
        </SelectPanel.Header>
        <ActionList sx={{minHeight: 340}}>
          {initialLoading ? (
            <SelectPanel.Loading>Fetching files and symbols&hellip;</SelectPanel.Loading>
          ) : groups.length === 0 && !filterLoading ? (
            <SelectPanel.Message variant="empty" title="No files or symbols found">
              Try a different search term
            </SelectPanel.Message>
          ) : (
            groups.map(group => (
              <ActionList.Group key={group.groupId}>
                <ActionList.GroupHeading variant="subtle">{group.title}</ActionList.GroupHeading>
                {items
                  .filter(item => item.groupId === group.groupId)
                  .map(item => (
                    <ReferenceListItem
                      key={item.id}
                      item={item}
                      selected={isSelected(item)}
                      onSelect={() =>
                        onSelectedChange(
                          isSelected(item)
                            ? selected.filter(selectedItem => selectedItem.id !== item.id)
                            : [...selected, item],
                        )
                      }
                    />
                  ))}
              </ActionList.Group>
            ))
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

function ReferenceListItem({onSelect, selected, item}: {onSelect: () => void; selected: boolean; item: Item}) {
  return (
    <ActionList.Item
      onSelect={onSelect}
      selected={selected}
      aria-checked={selected}
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
  groupId: string
}

interface Group {
  groupId: string
  title: string
}

const DISPLAYED_MATCHES_LIMIT = 7
const GROUP_SELECTIONS_ID = '0'
const GROUP_FILES_ID = '1'
const GROUP_SYMBOLS_ID = '2'
const DEFAULT_GROUPS: Group[] = [
  {groupId: GROUP_SELECTIONS_ID, title: 'Current attachments'},
  {groupId: GROUP_FILES_ID, title: 'Files'},
  {groupId: GROUP_SYMBOLS_ID, title: 'Symbols'},
]

/**
 * itemCache maps reference IDs to the selectable items that represent those references.
 * The SelectPanel uses `Object.is` to compare items, so it is important at any given
 * time for the selected items to be a subset of all items.
 * This cache is important because in some scenarios (e.g. when some of the selected
 * references are not currently in the filtered list of options) we do not get these
 * items from the query and only have the IDs.
 */
const itemCache = new Map<string, Item>()

interface ReferencesData extends QueriedItemsResult {
  selected: Item[]
  groups: Group[]
  onSelectedChange: (items: Item[]) => void
}

/**
 * useReferencesData handles managing the user's selection, and
 * applying that selection to the chat state.
 */
function useReferencesData(
  open: boolean,
  query: string,
  repo: CopilotChatRepo | null,
  workerPath: string,
): ReferencesData {
  const state = useChatState()
  const autocomplete = useChatAutocomplete()
  const [selectedIDs, setSelectedIDs] = useState<string[]>([])
  const queriedItemsResult = useQueriedItems(query, repo, workerPath, open)

  // When the panel opens, synchronize selections with the current state
  useEffect(() => {
    if (open) {
      const items = state.currentReferences.map(referenceToItem).filter(item => !!item)
      onSelectedChange(items)
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  const onSelectedChange = useCallback(
    (selected: Item[]) => {
      const newSelectedIds = selected.map(s => s.id).filter(id => typeof id === 'string')
      const newSelectedItems = newSelectedIds.map(id => itemCache.get(id)).filter(item => !!item)
      setSelectedIDs(newSelectedIds)
      void applySelectionsToState(newSelectedItems, state, autocomplete)
    },
    [autocomplete, state],
  )

  const selected = selectedIDs
    .map(id => itemCache.get(id))
    .filter(item => !!item)
    .map(item => ({...item, groupId: GROUP_SELECTIONS_ID}))

  const unselected = queriedItemsResult.items.filter(
    item => typeof item.id === 'string' && !selectedIDs.includes(item.id),
  )

  const items = [...selected, ...unselected]

  const groups = getGroups(items, queriedItemsResult.initialLoading || queriedItemsResult.filterLoading)

  return {
    ...queriedItemsResult,
    items,
    groups,
    selected,
    onSelectedChange,
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
  workerPath: string,
  open: boolean,
): QueriedItemsResult {
  const autocomplete = useChatAutocomplete()

  const {isLoading: autocompleteLoading, data} = useQuery({
    // eslint-disable-next-line @tanstack/query/exhaustive-deps
    queryKey: ['copilot-chat', 'files-autocomplete', repo?.ownerLogin, repo?.name, query],
    queryFn: async () => {
      if (!repo) return null

      await autocomplete.fetchAutocompleteSuggestions(repo, query)

      return {
        filePaths: Array.from(autocomplete.fileSuggestions.values()).map($result => $result.path),
        symbolNames: Array.from(autocomplete.symbolSuggestions.values()).map($result => $result.name),
      }
    },
    enabled: open,
  })

  const [matchingFiles, filesSearching] = useFilter(data?.filePaths ?? null, query, workerPath)
  const [matchingSymbols, symbolsSearching] = useFilter(data?.symbolNames ?? null, query, workerPath)

  const fileItems: Item[] = matchingFiles
    .slice(0, DISPLAYED_MATCHES_LIMIT)
    .map(e => autocomplete.fileSuggestions.get(e))
    .filter((item): item is FileReference => !!item)
    .map(item => referenceToItem(item))
    .filter((item): item is Item => !!item)

  const symbolItems: Item[] = matchingSymbols
    .slice(0, DISPLAYED_MATCHES_LIMIT)
    .map(e => autocomplete.symbolSuggestions.get(e))
    .filter((item): item is SuggestionSymbolReference => !!item)
    .map(item => referenceToItem(item))
    .filter((item): item is Item => !!item)

  const items = [...fileItems, ...symbolItems]

  const initialLoading = autocompleteLoading && !query
  const filterLoading = !initialLoading && (autocompleteLoading || filesSearching || symbolsSearching)

  return {items, filterLoading, initialLoading}
}

function referenceToItem(reference: CopilotChatReference): Item | undefined {
  const refID = referenceID(reference)

  const cached = itemCache.get(refID)
  if (cached) return cached

  let itemInput: Item | undefined
  switch (reference.type) {
    case 'symbol':
      itemInput = {
        id: refID,
        key: refID,
        renderLeadingVisual: () => <CodeSquareIcon />,
        text: reference.name,
        groupId: GROUP_SYMBOLS_ID,
      }
      break
    case 'file':
      itemInput = {
        id: refID,
        key: refID,
        renderLeadingVisual: () => <FileIcon />,
        text: reference.path,
        groupId: GROUP_FILES_ID,
      }
      break
    case 'file-diff':
      itemInput = {
        id: refID,
        key: refID,
        renderLeadingVisual: () => <FileDiffIcon />,
        text: fileDiffRefName(reference),
        groupId: GROUP_FILES_ID,
      }
      break
  }

  if (!itemInput) return undefined

  itemCache.set(refID, itemInput)
  return itemInput
}

function getGroups(items: Item[], loading: boolean): Group[] {
  if (items.length === 0 && !loading) {
    return []
  }

  const activeGroups: Group[] = []

  for (const group of DEFAULT_GROUPS) {
    const found = items.find(_item => _item.groupId === group.groupId) !== undefined
    if (found) {
      activeGroups.push(group)
    }
  }

  return activeGroups
}

async function applySelectionsToState(
  selections: Item[],
  state: CopilotChatState,
  autocomplete: CopilotAutocompleteManager,
) {
  // Clear up removed references, iterate over current state selections
  for (const currentReference of state.currentReferences) {
    // try to find that selection in the dialogs selections
    const nameWithKey = referenceID(currentReference)

    const existing = selections.find(selection => selection.id === nameWithKey)
    if (!existing) {
      autocomplete.manager.removeReference(state.currentReferences.findIndex(ref => referenceID(ref) === nameWithKey))
    }
  }

  const promises: Array<Promise<void>> = []

  // Handle new references
  for (const selection of selections) {
    if (selection.id && typeof selection.id === 'string' && selection.text) {
      const symbolSelection = autocomplete.symbolSuggestions.get(selection.text)
      const fileSelection = autocomplete.fileSuggestions.get(selection.text)

      if (symbolSelection) {
        promises.push(autocomplete.addToReferences(symbolSelection, state))
      }
      if (fileSelection) {
        promises.push(autocomplete.addToReferences(fileSelection, state))
      }
    }
  }

  await Promise.all(promises)
}
