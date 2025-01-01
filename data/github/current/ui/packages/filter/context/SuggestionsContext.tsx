import {useLayoutEffect} from '@github-ui/use-layout-effect'
import type {AnchorPosition} from '@primer/behaviors'
import type React from 'react'
import {createContext, useCallback, useContext, useMemo, useRef, useState} from 'react'

import {Strings} from '../constants/strings'
import type {FilterQuery} from '../filter-query'
import {useDelimiterAnchorPosition} from '../hooks/use-delimiter-anchor-position'
import {
  BlockType,
  type FilterSuggestion,
  type FilterSuggestionGroup,
  FilterValueType,
  type IndexedFilterBlock,
} from '../types'
import {
  checkFilterQuerySync,
  getEscapedFilterValue,
  getFilterBlockChunkByCaret,
  getFilterValue,
  getLastFilterBlockValue,
  getUnescapedFilterValue,
  isIndexedFilterBlock,
} from '../utils'
import {updateScreenReaderFeedback} from '../utils/accessibility'
import {useFilterQuery} from './FilterQueryContext'
import {useFilter} from './RootContext'

interface SuggestionsContext {
  activeSuggestion: number
  hideSuggestions: () => void
  isFetchingSuggestions: boolean
  position?: AnchorPosition
  suggestionGroups: FilterSuggestionGroup[]
  showSuggestions: () => void
  suggestionsListRef: React.RefObject<HTMLDivElement>
  suggestionSelected: (value: FilterSuggestion) => void
  suggestionsVisible?: boolean
  updateSuggestions: (query: FilterQuery, caret?: number, shouldShowSuggestions?: boolean) => Promise<void>
  activeSuggestionRef: React.MutableRefObject<HTMLLIElement | null>
  setActiveSuggestion: React.Dispatch<React.SetStateAction<number>>
}

export const SuggestionsContext = createContext<SuggestionsContext | undefined>(undefined)

export const useSuggestions = () => {
  const context = useContext(SuggestionsContext)
  if (!context) {
    throw new Error('useSuggestions must be used inside a SuggestionsContext')
  }

  return context
}

export const MAXIMUM_SUGGESTIONS_TO_SHOW = 25

interface SuggestionsContextProviderProps {
  caretRef: React.RefObject<HTMLSpanElement>
  children: React.ReactNode
  inputRef: React.RefObject<HTMLInputElement>
}

function excludeUsedSuggestions(suggestionGroup: FilterSuggestionGroup, activeFilterBlock?: IndexedFilterBlock) {
  const values = (activeFilterBlock?.value.values ?? []).map(value => getUnescapedFilterValue(value.value))
  const suggestions = suggestionGroup.suggestions.filter(suggestion => {
    const suggestionValue = getFilterValue(suggestion.value) ?? ''
    return !values.includes(suggestionValue)
  })

  return {
    ...suggestionGroup,
    suggestions,
  }
}

export const SuggestionsContextProvider = ({children, caretRef, inputRef}: SuggestionsContextProviderProps) => {
  const {config, inputContextRef} = useFilter()
  const {
    filterQuery,
    filterProviders,
    insertIntoQuery,
    rawFilterRef,
    replaceActiveBlockWithPresenceBlock,
    updateFilter,
    updateFromExternal,
  } = useFilterQuery()

  const activeSuggestionRef = useRef<HTMLLIElement | null>(null)
  const suggestionsListRef = useRef<HTMLDivElement>(null)

  const {position, updatePosition} = useDelimiterAnchorPosition(
    {
      caretElementRef: caretRef,
      floatingElementRef: suggestionsListRef,
      inputElementRef: inputRef,
      side: 'outside-bottom',
      align: 'start',
      alignmentOffset: -16,
      allowOutOfBounds: false,
    },

    [suggestionsListRef.current, inputContextRef.current?.styledInputBlockCount],
  )

  const [isFetchingSuggestions, setIsFetchingSuggestions] = useState(false)
  const [suggestionsVisible, setSuggestionsVisible] = useState(false)
  const [suggestionGroups, setSuggestionGroups] = useState<FilterSuggestionGroup[]>([])
  const [activeSuggestion, setActiveSuggestion] = useState<number>(-1)

  const showSuggestions = useCallback(() => {
    if (suggestionsVisible) return
    setSuggestionsVisible(true)
  }, [suggestionsVisible])
  const hideSuggestions = useCallback(() => {
    setSuggestionsVisible(false)
    setActiveSuggestion(-1)
  }, [])

  const updateSuggestions = useCallback(
    async (filter?: FilterQuery, caret?: number) => {
      let internalShouldShowSuggestions = true
      // If there is no filter input, don't show suggestions
      if (config.variant === 'button') return

      // If the user is currently composing a character (IME support), don't show suggestions
      if (inputContextRef.current?.isComposing) return

      // Reset the initial state to empty
      setSuggestionGroups([])
      // Update the position first so we show we're responding
      updatePosition()

      // Prioritize the filter passed in, otherwise use the current filter from state
      const query = filter ?? filterQuery
      const caretIndex = caret ?? inputRef.current?.selectionStart ?? -1

      let cachedSuggestionGroup: FilterSuggestionGroup = {id: 'cached-suggestions', suggestions: []}
      let cachedWithoutUsedSuggestionGroup = cachedSuggestionGroup
      let aggregatedSuggestionGroups: FilterSuggestionGroup[] = []
      const activeBlock = query.activeBlock
      const activeFilterBlock = activeBlock && isIndexedFilterBlock(activeBlock) ? activeBlock : undefined

      const queryValue = activeBlock ? getLastFilterBlockValue(activeBlock, caretIndex) : ''

      const isCompleteResultSetQueryOrTextBlockOrOtherTypeOfNonSpecificBlock =
        queryValue && activeFilterBlock && activeFilterBlock.provider?.isCompleteResultSetQuery?.(queryValue)

      // Before fetching async, we will check the provider for any pre-fetched suggestions that match the current filter value
      if (activeFilterBlock) {
        const [type] = getFilterBlockChunkByCaret(activeFilterBlock, caretIndex)

        // Look for cached suggestions if the caret is positioned on the value, and only if it even has a value
        if (type === 'value' && queryValue) {
          cachedSuggestionGroup = {
            id: 'cached-suggestions',
            suggestions: activeFilterBlock.provider?.findPrefetchedSuggestions?.(queryValue) ?? [],
          }
          cachedWithoutUsedSuggestionGroup = excludeUsedSuggestions(cachedSuggestionGroup, activeFilterBlock)

          if (cachedWithoutUsedSuggestionGroup && cachedWithoutUsedSuggestionGroup.suggestions.length > 0) {
            // Make sure the menu is visible to prevent it from flashing
            showSuggestions()

            updateScreenReaderFeedback(
              `${cachedWithoutUsedSuggestionGroup.suggestions.length} ${
                cachedWithoutUsedSuggestionGroup.suggestions.length === 1 ? 'suggestion' : 'suggestions'
              }`,
            )

            // Immediately put any cached suggestions into the suggestions list while we wait for
            // any additional suggestions to come async so the user sees immediate feedback.
            setSuggestionGroups([cachedWithoutUsedSuggestionGroup])
          }
        }
      }

      // We only want to fetch async suggestions if there aren't enough cached suggestions to fill the list.
      // This should always be the case if prefetching is disabled, as the cachedSuggestions array is empty.
      if (
        cachedWithoutUsedSuggestionGroup.suggestions.length < MAXIMUM_SUGGESTIONS_TO_SHOW &&
        !isCompleteResultSetQueryOrTextBlockOrOtherTypeOfNonSpecificBlock
      ) {
        // Notify state we are beginning to fetch
        if (activeFilterBlock && activeFilterBlock.provider?.isCompleteResultSetQuery?.(queryValue) !== undefined) {
          setIsFetchingSuggestions(true)
        }

        aggregatedSuggestionGroups = await query.getSuggestions(caretIndex, filterProviders, config)

        // Keep the cached suggestions at the front of the list to prevent the results from shifting away from the user.
        aggregatedSuggestionGroups[0]?.suggestions.unshift(...cachedSuggestionGroup.suggestions)

        // Remove any duplicates
        const seen = new Set<string>()
        if (aggregatedSuggestionGroups[0]) {
          aggregatedSuggestionGroups[0].suggestions = aggregatedSuggestionGroups[0]?.suggestions.filter(suggestion => {
            const key = getFilterValue(suggestion.value) ?? ''
            return seen.has(key) ? false : seen.add(key)
          })
        }

        if (aggregatedSuggestionGroups[0] && activeBlock?.type === BlockType.Text && activeBlock.raw.startsWith('-')) {
          aggregatedSuggestionGroups[0].title = Strings.exclude
        }
      } else {
        // If we have enough cached suggestions to fill the list, just use those
        aggregatedSuggestionGroups = [cachedSuggestionGroup]
      }

      if (activeFilterBlock) {
        // Hide suggestion if the first suggestion is the currently entered filter value
        const indexedValue = getLastFilterBlockValue(activeFilterBlock, caretIndex)
        const firstGroupsSuggestions = aggregatedSuggestionGroups[0]?.suggestions
        if (
          aggregatedSuggestionGroups.length === 1 &&
          firstGroupsSuggestions &&
          getFilterValue(firstGroupsSuggestions[0]?.value) === indexedValue &&
          indexedValue.length > 0
        ) {
          // If there are no more suggestions
          if (firstGroupsSuggestions.length === 1) {
            internalShouldShowSuggestions = false
          } else {
            // Hide suggestion only if there are no more suggestions with a matching prefix
            const matchingPrefixSuggestions = firstGroupsSuggestions.filter(suggestion => {
              const suggestionValue = getFilterValue(suggestion.value)
              return suggestionValue !== indexedValue && suggestionValue?.startsWith(indexedValue)
            })
            if (matchingPrefixSuggestions.length === 0) {
              internalShouldShowSuggestions = false
            }
          }
        }
      }

      if (aggregatedSuggestionGroups[0]) {
        // Exclude any values that are already in the filter
        aggregatedSuggestionGroups[0] = excludeUsedSuggestions(aggregatedSuggestionGroups[0], activeFilterBlock)
        // Limit the number of suggestions to show
        aggregatedSuggestionGroups[0].suggestions = aggregatedSuggestionGroups[0].suggestions.slice(
          0,
          MAXIMUM_SUGGESTIONS_TO_SHOW,
        )
      }

      if (checkFilterQuerySync(query, rawFilterRef?.current) && query.isValidated) {
        // Final check to make sure the query hasn't changed while we were fetching suggestions and that is validated
        const suggestionCounts = aggregatedSuggestionGroups.reduce((n, group) => n + group.suggestions.length, 0)

        // Ensure we only announce available suggestions if the user is focused on the input
        if (document.activeElement === inputRef.current) {
          updateScreenReaderFeedback(
            `${suggestionCounts} ${suggestionCounts === 1 ? 'suggestion' : 'suggestions'}`,
            false,
          )
        }

        setSuggestionGroups(aggregatedSuggestionGroups)
        // Reset the active suggestion if we replace the entire contents of the list
        if (cachedSuggestionGroup.suggestions.length === 0) setActiveSuggestion(-1)

        if (
          aggregatedSuggestionGroups.length > 0 &&
          internalShouldShowSuggestions &&
          inputContextRef.current?.inputHasFocus
        ) {
          showSuggestions()
        } else {
          hideSuggestions()
        }
      }

      setIsFetchingSuggestions(false)
    },
    [
      config,
      filterQuery,
      inputRef,
      filterProviders,
      showSuggestions,
      updatePosition,
      rawFilterRef,
      inputContextRef,
      hideSuggestions,
    ],
  )

  const suggestionSelected = useCallback(
    (suggestion: FilterSuggestion) => {
      setActiveSuggestion(-1)
      const currentBlock = filterQuery.activeBlock
      const isExcludeKeySuggestion = suggestion.value.toString().startsWith('-')

      let suggestedValue
      let shouldSubmit = false

      // If the user selects the Divider, we abort early and do nothing
      if (suggestion.value === Strings.dividerValue) return

      // Selected Filter Key
      if (suggestion.type === 'keyword') {
        suggestedValue = getEscapedFilterValue(suggestion.value)
      } else if (!currentBlock || currentBlock.type !== BlockType.Filter) {
        suggestedValue = getEscapedFilterValue(suggestion.value)

        // only add the colon if the suggestion value is NOT the exclude key and doesn't end with a dot,
        // indicating a nested filter key
        if (suggestedValue !== '-' && !suggestedValue?.endsWith('.')) {
          suggestedValue += config.filterDelimiter
        }
        // Selected Filter Value
      } else if (isExcludeKeySuggestion) {
        suggestedValue = getEscapedFilterValue(suggestion.value)
      } else {
        suggestedValue = getEscapedFilterValue(suggestion.value)
        shouldSubmit = true
        hideSuggestions()
      }

      const caretIndex = inputRef.current?.selectionStart ?? -1

      if (suggestion.type === FilterValueType.NoValue) {
        replaceActiveBlockWithPresenceBlock('no')
      } else if (suggestion.type === FilterValueType.HasValue) {
        replaceActiveBlockWithPresenceBlock('has')
      } else if (suggestedValue) {
        insertIntoQuery(suggestedValue, caretIndex, shouldSubmit)
      } else {
        updateFilter()
      }
    },
    [
      config.filterDelimiter,
      filterQuery.activeBlock,
      hideSuggestions,
      inputRef,
      insertIntoQuery,
      replaceActiveBlockWithPresenceBlock,
      updateFilter,
    ],
  )

  useLayoutEffect(() => {
    updateFromExternal(async query => {
      if (checkFilterQuerySync(query, rawFilterRef?.current)) {
        await updateSuggestions(query, inputRef.current?.selectionStart ?? -1)
      }
    })
  }, [rawFilterRef, updateSuggestions, filterQuery.raw, filterQuery, updateFromExternal, inputRef])

  const suggestionsContextValue = useMemo(
    () => ({
      activeSuggestion,
      hideSuggestions,
      isFetchingSuggestions,
      position,
      showSuggestions,
      suggestionGroups,
      suggestionsListRef,
      suggestionSelected,
      suggestionsVisible,
      setActiveSuggestion,
      updateSuggestions,
      activeSuggestionRef,
    }),
    [
      activeSuggestion,
      activeSuggestionRef,
      hideSuggestions,
      isFetchingSuggestions,
      position,
      showSuggestions,
      suggestionGroups,
      suggestionSelected,
      suggestionsVisible,
      updateSuggestions,
    ],
  )

  return <SuggestionsContext.Provider value={suggestionsContextValue}>{children}</SuggestionsContext.Provider>
}
