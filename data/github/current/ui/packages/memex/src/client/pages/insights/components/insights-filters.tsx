import {type ChangeEventHandler, useMemo} from 'react'

import {
  FilterSuggestionsItemsContext,
  type FilterSuggestionsItemsContextProps,
} from '../../../components/filter-bar/filter-suggestions'
import {TokenizedFilterInput} from '../../../components/filter-bar/tokenized-filter-input'
import {useMemexItems} from '../../../state-providers/memex-items/use-memex-items'

type InsightsFilterProps = {
  filterValue: string
  // The number of project items matching the filterValue
  filterCount?: number | undefined
  handleFilterValueChange: ChangeEventHandler<HTMLInputElement>
  handleNewFilterBarValueChange: (value: string) => void
  onClearButtonClick: React.MouseEventHandler<HTMLButtonElement> | undefined
  setValueFromSuggestion: (value: string) => void
  onSaveChanges?: (() => void) | undefined
  onResetChanges?: (() => void) | undefined
  inputRef: React.RefObject<HTMLInputElement | null> | undefined
  hideSaveButton?: boolean
}

export const InsightsFilters = ({
  filterCount,
  filterValue,
  handleFilterValueChange,
  handleNewFilterBarValueChange,
  onClearButtonClick,
  setValueFromSuggestion,
  onSaveChanges,
  onResetChanges,
  inputRef,
  hideSaveButton,
}: InsightsFilterProps) => {
  const {items} = useMemexItems()

  const contextValue: FilterSuggestionsItemsContextProps = useMemo(() => {
    return {
      items,
    }
  }, [items])

  return (
    <FilterSuggestionsItemsContext.Provider value={contextValue}>
      <TokenizedFilterInput
        inputRef={inputRef}
        height="32px"
        value={filterValue}
        onChange={handleFilterValueChange}
        onChangeValue={handleNewFilterBarValueChange}
        onClearButtonClick={onClearButtonClick}
        setValueFromSuggestion={setValueFromSuggestion}
        filterCount={filterCount}
        onSaveChanges={onSaveChanges}
        onResetChanges={onResetChanges}
        hideSaveButton={hideSaveButton}
      />
    </FilterSuggestionsItemsContext.Provider>
  )
}
