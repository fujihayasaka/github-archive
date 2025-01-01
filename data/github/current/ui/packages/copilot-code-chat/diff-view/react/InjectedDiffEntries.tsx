import type {FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useMemo, useRef, useState, useSyncExternalStore} from 'react'
import {createPortal} from 'react-dom'
import {CopilotDiffEntryElement} from '../rails/CopilotDiffEntryElement'
import {DiffLinesMenu} from '../rails/DiffLinesMenu'
import {type ActiveLines, useActiveDiffLines} from '../rails/use-active-diff-lines'
import {DiffEntryMenuItems} from '../shared/DiffEntryMenuItems'
import type {DiffEntryData} from '../shared/use-get-diff-entry-data'

const useEntryElements = () =>
  useSyncExternalStore(
    onUpdate => {
      CopilotDiffEntryElement.store.addEventListener('update', onUpdate)
      return () => CopilotDiffEntryElement.store.removeEventListener('update', onUpdate)
    },
    () => CopilotDiffEntryElement.store.entries,
  )

interface InjectedDiffButtonProps {
  fileDiffReference: FileDiffReference
  activeLines?: ActiveLines
}

const InjectedDiffButton: React.FC<InjectedDiffButtonProps> = ({fileDiffReference, activeLines: newActiveLines}) => {
  const [isMenuOpen, setIsMenuOpen] = useState(false)

  const lastActiveLines = useRef(newActiveLines)

  // Force continued usage of previous value if menu is still open, so we don't autoclose the menu when the user tries
  // to move the mouse into it
  // eslint-disable-next-line react-compiler/react-compiler
  const activeLines = isMenuOpen ? lastActiveLines.current : newActiveLines
  // eslint-disable-next-line react-compiler/react-compiler
  lastActiveLines.current = activeLines

  if (!activeLines) return null

  const fileDiffReferenceWithSelection = {
    ...fileDiffReference,
    selectedRange: {
      start: `${activeLines.startOrientation[0]?.toUpperCase() ?? ''}${activeLines.startLineNumber}`,
      end: `${activeLines.endOrientation[0]?.toUpperCase() ?? ''}${activeLines.endLineNumber}`,
    },
  }

  return createPortal(
    <DiffLinesMenu fileDiffReference={fileDiffReferenceWithSelection} onOpenChange={setIsMenuOpen} />,
    activeLines.topRightElement,
  )
}

interface InjectedDiffEntryProps {
  entryElement: CopilotDiffEntryElement
  fileDiffReference: DiffEntryData['reference']
  activeLines?: ActiveLines
}

const InjectedDiffEntry: React.FC<InjectedDiffEntryProps> = ({
  entryElement: {menuItemsSlot},
  fileDiffReference,
  activeLines,
}) => (
  <>
    {fileDiffReference && <InjectedDiffButton fileDiffReference={fileDiffReference} activeLines={activeLines} />}
    {menuItemsSlot && createPortal(<DiffEntryMenuItems fileDiffReference={fileDiffReference} />, menuItemsSlot)}
  </>
)

interface InjectedDiffEntriesProps {
  entriesData: DiffEntryData[]
}

export const InjectedDiffEntries: React.FC<InjectedDiffEntriesProps> = ({entriesData}) => {
  const entryElements = useEntryElements()
  const activeLinesById = useActiveDiffLines()

  // kinda gross but basically builds + memos the entry components we need in as few loops as possible
  const injectedEntries = useMemo(() => {
    const entries: React.ReactElement[] = []

    // need to be able to find a FileDiffReference by filePath
    const entriesFilePathMap = entriesData.reduce((map, entry) => {
      if (entry.reference) map.set(entry.path, entry.reference)
      return map
    }, new Map<string, FileDiffReference>())

    Array.from(entryElements).map(entryElement => {
      const reference = entriesFilePathMap.get(entryElement.filePath)
      if (reference) {
        entries.push(
          <InjectedDiffEntry
            key={entryElement.filePath}
            entryElement={entryElement}
            fileDiffReference={reference}
            activeLines={activeLinesById.get(reference.id)}
          />,
        )
      }
    })

    return entries
  }, [activeLinesById, entriesData, entryElements])

  return injectedEntries
}
