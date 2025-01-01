import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {useId, useState} from 'react'

import type {DisplayTaskData} from '../../utilities/workspace-editor-types'
import styles from './ExpandableSuggestions.module.css'
import {SuggestionsList} from './SuggestionsList'

/**
 * Render a list of suggestions that can be expanded or collapsed.
 */
export function ExpandableSuggestions({
  defaultOpen = false,
  description,
  filteredSuggestionsMap,
  onTaskSelected,
}: {
  defaultOpen?: boolean
  description: string
  filteredSuggestionsMap: Array<[string, DisplayTaskData]>
  onTaskSelected: (taskSourceId: number) => void
}) {
  const [isOpen, setOpen] = useState(defaultOpen)
  const groupContentId = useId()

  if (!filteredSuggestionsMap.length) return null

  return (
    <div className="d-flex flex-column mt-2">
      <span>
        <Button
          aria-controls={groupContentId}
          aria-expanded={isOpen}
          className={styles.expandButton}
          onClick={() => setOpen(!isOpen)}
          size="small"
          trailingVisual={() => (isOpen ? <ChevronDownIcon /> : <ChevronRightIcon />)}
          variant="invisible"
        >
          {description}
        </Button>
      </span>
      {isOpen && (
        <SuggestionsList id={groupContentId} suggestionsMap={filteredSuggestionsMap} onTaskSelected={onTaskSelected} />
      )}
    </div>
  )
}
