import {useIgnoreKeyboardActionsWhileComposing} from '@github-ui/use-ignore-keyboard-actions-while-composing'
import type {TextInputProps} from '@primer/react'
import debounce, {type DebouncedFunc} from 'lodash-es/debounce'
import {useCallback, useEffect, useId, useRef, useState} from 'react'
import type {SpaceProps, TypographyProps} from 'styled-system'

import {apiSearchRepositories} from '../../api/repository/api-search-repositories'
import type {SuggestedRepository} from '../../api/repository/contracts'
import type {GroupingMetadataWithSource} from '../../features/grouping/types'
import type {FuzzyFilterPositionData} from '../../helpers/suggester'
import {useTextExpander} from '../../hooks/common/use-text-expander'
import {useRepositories} from '../../state-providers/repositories/use-repositories'
import {Resources} from '../../strings'
import {OmnibarPlaceholder} from '../omnibar/omnibar-placeholder'
import type {OmnibarMenu} from '../omnibar/types'
import {BaseCell} from './cells/base-cell'
import {RepoList} from './repo-list'
import styles from './repo-searcher.module.css'

export interface RepoSearcherProps {
  omnibarText: string
  setOmnibarText: (newText: string) => void
  onRepositorySelected: (repository: SuggestedRepository | null) => void
  inputRef: React.RefObject<HTMLInputElement>
  renderInput: (props: TextInputProps & TypographyProps & SpaceProps) => React.ReactNode
  setOmnibarMenu: (value: OmnibarMenu) => void

  /** The default placeholder to show when the omnibar does not have focus */
  defaultPlaceholder: React.ReactNode
  /** Initial value for the focused state, used to avoid inconsistencies between focused state from the parent and here */
  isFocused?: boolean
  /** Whether the repo searcher is disabled*/
  isDisabled?: boolean

  /** Grouped-by metadata, such as repo or issue type **/
  groupingMetadata?: GroupingMetadataWithSource
}

export const RepoSearcher: React.FC<RepoSearcherProps> = ({
  onRepositorySelected,
  omnibarText,
  setOmnibarText,
  inputRef,
  renderInput,
  defaultPlaceholder,
  isFocused,
  isDisabled,
  groupingMetadata,
  setOmnibarMenu,
}) => {
  const {suggestRepositories: fetchRepositorySuggestions} = useRepositories()
  const [refreshing, setRefreshing] = useState(false)
  const [suggestions, setSuggestions] = useState<Array<SuggestedRepository> | undefined>()
  const [searchResults, setSearchResults] = useState<Array<SuggestedRepository> | undefined>()
  const [positionDataMap, setPositionDataMap] = useState(
    () => new WeakMap<SuggestedRepository, FuzzyFilterPositionData>(),
  )
  const debouncedSearch = useRef<DebouncedFunc<() => Promise<void>> | undefined>(undefined)
  const isFirstRender = useRef(true)
  const [inputHasFocus, setInputHasFocus] = useState(!!isFocused)
  const groupedByIssueType =
    groupingMetadata?.sourceObject.dataType === 'issueType' && groupingMetadata.sourceObject.kind === 'group'
  const milestoneGroupingTitle =
    groupingMetadata?.sourceObject.dataType === 'milestone' && groupingMetadata.sourceObject.kind === 'group'
      ? groupingMetadata.value
      : undefined

  const displaySearchResults = useCallback(
    (repos: Array<SuggestedRepository>) => {
      // This allows us to display text for each result, but disables highlighting of matched
      // terms within the result text.
      const dummyPositionData = repos.reduce((map, repo) => {
        map.set(repo, {chunks: [{startIndex: 0, endIndex: repo.name.length, highlight: false}]})
        return map
      }, new WeakMap<SuggestedRepository, FuzzyFilterPositionData>())

      setSearchResults(repos)
      setPositionDataMap(dummyPositionData)
      setRefreshing(false)
    },
    [setSearchResults, setPositionDataMap],
  )

  const inputOnChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      setOmnibarText(e.target.value)

      if (!e.target.value.length) {
        setOmnibarMenu(null)
      }
    },
    [setOmnibarText, setOmnibarMenu],
  )

  const searchRepositories = useCallback(
    async (query: string) => {
      const results = query
        ? await apiSearchRepositories({
            query,
            onlyWithIssueTypes: groupedByIssueType,
            milestone: milestoneGroupingTitle,
          })
        : undefined

      // Now that we've received results from the server, only show the new results if the
      // user hasn't since cleared the input of a real query.
      // This is a very special case where we need to know the most current input value,
      // which isn't updated into omnibarText in time for this event handler.
      if (inputRef.current?.value !== '#') {
        displaySearchResults(results?.repositories ?? suggestions ?? [])
      }
    },
    [displaySearchResults, suggestions, groupedByIssueType, milestoneGroupingTitle, inputRef],
  )

  const enqueueRepositorySearch = useCallback(
    (textExpanderText: string) => {
      if (debouncedSearch.current) {
        debouncedSearch.current.cancel()
      }

      debouncedSearch.current = debounce(() => searchRepositories(textExpanderText), 200)

      setRefreshing(true)
      debouncedSearch.current()
    },
    [debouncedSearch, searchRepositories, setRefreshing],
  )

  const onSelectedItemChange = (item: SuggestedRepository) => {
    onRepositorySelected(item)
  }

  const textExpanderOnChange = (textExpanderText: string) => {
    if (!textExpanderText && suggestions) {
      displaySearchResults(suggestions)
    }

    if (textExpanderText) {
      enqueueRepositorySearch(textExpanderText)
    }
  }

  const {getInputProps, getListProps, getItemProps, isOpen} = useTextExpander(
    {
      textExpanderOnChange,
      items: searchResults || [],
      onSelectedItemChange,
      inputValue: omnibarText,
    },
    inputRef,
  )

  const inputOnKeyDown = useCallback(
    async (event: React.KeyboardEvent<HTMLInputElement>) => {
      if (event.target instanceof HTMLInputElement || event.target instanceof HTMLInputElement) {
        const inputEl = event.target
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        switch (event.key) {
          case 'Escape':
            if (isOpen) {
              setOmnibarText('')
              setOmnibarMenu(null)
              event.stopPropagation()
            }
            break

          case 'ArrowLeft':
            if (inputEl.selectionStart !== 0 || inputEl.selectionEnd !== 0) {
              event.nativeEvent['preventFocusChange'] = true
            }
            break

          case 'ArrowRight':
            if (inputEl.selectionStart !== inputEl.value.length || inputEl.selectionEnd !== inputEl.value.length) {
              event.nativeEvent['preventFocusChange'] = true
            }
            break
          case 'ArrowDown':
          case 'ArrowUp':
            if (isOpen) {
              // Do not propagate arrow key presses when open, as
              // they're used for cell navigation.
              event.stopPropagation()
            }
            break
        }
      }
    },
    [isOpen, setOmnibarText, setOmnibarMenu],
  )

  const inputCompositionProps = useIgnoreKeyboardActionsWhileComposing(inputOnKeyDown)

  useEffect(() => {
    const loadSuggestions = async () => {
      if (suggestions === undefined) {
        setRefreshing(true)

        const newSuggestions = await fetchRepositorySuggestions({
          onlyWithIssueTypes: groupedByIssueType,
          milestone: milestoneGroupingTitle,
        })
        setSuggestions(newSuggestions)

        // This is a very special case where we need to know the most current input value,
        // which isn't updated into omnibarText in time for this function execution.
        if (inputRef.current?.value === '#') {
          displaySearchResults(newSuggestions)
        }
      }
    }

    if (isFirstRender.current) {
      isFirstRender.current = false
      loadSuggestions()
    }
  }, [
    suggestions,
    setSuggestions,
    fetchRepositorySuggestions,
    displaySearchResults,
    groupedByIssueType,
    milestoneGroupingTitle,
    omnibarText,
    inputRef,
  ])

  useEffect(() => {
    if (inputRef.current && isFocused) {
      inputRef.current?.focus()
    }
  }, [inputRef, isFocused])

  const inputOnFocus: React.FocusEventHandler = useCallback(() => {
    if (isDisabled) return
    setInputHasFocus(true)
  }, [isDisabled])

  const inputOnBlur: React.FocusEventHandler = useCallback(() => {
    if (isDisabled) return
    setInputHasFocus(false)
  }, [isDisabled])

  const omnibarDescriptionId = useId()
  const input = isDisabled ? (
    <BaseCell aria-disabled="true" className={styles.BaseCell}>
      {defaultPlaceholder}
    </BaseCell>
  ) : (
    renderInput({
      ...getInputProps({onChange: inputOnChange, onFocus: inputOnFocus, onBlur: inputOnBlur}),
      pl: '12px',
      fontSize: 1,
      lineHeight: 1.5,
      'aria-label': Resources.newItemPlaceholderAriaLabel,
      'aria-describedby': omnibarDescriptionId,
      'aria-keyshortcuts': 'Control+Space',
      autoComplete: 'off',
      value: omnibarText,
      ...inputCompositionProps,
    })
  )

  return (
    <div className={styles.Box}>
      <OmnibarPlaceholder
        descriptionId={omnibarDescriptionId}
        focusedPlaceholder={Resources.newItemPlaceholder}
        inputHasFocus={inputHasFocus}
        unfocusedPlaceholder={defaultPlaceholder}
        value={omnibarText}
      />
      {input}
      <RepoList
        {...getListProps()}
        inputRef={inputRef}
        isOpen={isOpen}
        loading={refreshing}
        positionDataMap={positionDataMap}
        getItemProps={getItemProps}
        repositories={searchResults || []}
      />
    </div>
  )
}
