import {useRefObjectAsForwardedRef} from '@primer/react'
import type React from 'react'
import {createContext, forwardRef, useCallback, useContext, useImperativeHandle, useMemo, useRef, useState} from 'react'

import {type FilterConfig, SubmitEvent} from '../types'
import {checkFilterQuerySync, findMatchedQuotes, getFlatSuggestionsList} from '../utils'
import {useFilter} from '.'
import {useFilterQuery} from './FilterQueryContext'
import {useSuggestions} from './SuggestionsContext'

interface InputContext {
  caretRef: React.RefObject<HTMLSpanElement>
  inputFocused: boolean
  inputKeyDown: React.KeyboardEventHandler
  inputOnCompositionStart: React.CompositionEventHandler
  inputOnCompositionEnd: React.CompositionEventHandler
  inputOnChange: React.ChangeEventHandler
  inputOnFocus: React.FocusEventHandler
  inputOnBlur: React.FocusEventHandler
  inputRef: React.RefObject<HTMLInputElement>
  inputSelectionEnd: number
  inputSelectionStart: number
  inputValue: string
  updateStyledInputBlockCount: (count: number) => void
  suspendFocus: (element: HTMLElement) => void
  updateInputSelection: (selectionStart: number, selectionEnd?: number) => void
}

export const InputContext = createContext<InputContext | undefined>(undefined)

export const useInput = () => {
  const context = useContext(InputContext)
  if (!context) {
    throw new Error('useInput must be used inside a InputContext')
  }

  return context
}

interface InputContextProviderProps {
  caretRef: React.RefObject<HTMLSpanElement> | null
  children: React.ReactNode
  inputRef: React.RefObject<HTMLInputElement> | null
  value: string
  filterConfig: FilterConfig
}

export type InputContextRef = {
  updateCaretPosition: (start: number, end?: number) => void
  caretStart: number
  caretEnd: number
  isComposing: boolean
  inputHasFocus: boolean
  styledInputBlockCount: number
  updateRawFilterValue: (value: string) => void
}

// Updates the native input value, sets the selection range, and dispatches a React change event
const updateNativeInputElement = (
  input: HTMLInputElement,
  value: string,
  selectionStartIndex: number,
  selectionEndIndex?: number,
): void => {
  // Need to use input's native setter to dispatch React change event
  const nativeInputValueProperty = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')
  const nativeInputValueSetter = (v: string) => nativeInputValueProperty?.set?.call(input, v)
  nativeInputValueSetter(value)
  input.setSelectionRange(selectionStartIndex, selectionEndIndex ?? selectionStartIndex)
  input.dispatchEvent(new Event('input', {bubbles: true}))
  // Fix storybook userEvent.keyboard because it uses React's setter
  input.value = value
}

export const InputContextProvider = forwardRef<InputContextRef, InputContextProviderProps>(
  (
    {
      caretRef: forwardedCaretRef = null,
      children,
      inputRef: forwardedInputRef = null,
      value: externalValue = '',
      filterConfig,
    },
    ref,
  ) => {
    const caretRef = useRef<HTMLSpanElement>(null)
    useRefObjectAsForwardedRef(forwardedCaretRef, caretRef)
    const inputRef = useRef<HTMLInputElement>(null)
    useRefObjectAsForwardedRef(forwardedInputRef, inputRef)
    const [isInteractingWithSuggestions, setIsInteractingWithSuggestions] = useState(false)
    const [isInputFocused, setIsInputFocused] = useState(false)
    const [inputSelectionStart, setInputSelectionStart] = useState(-1)
    const [inputSelectionEnd, setInputSelectionEnd] = useState(-1)

    const isComposing = useRef<boolean>(false)
    const [filterValue, setFilterValue] = useState(externalValue)

    const styledInputBlockCount = useRef<number>(0)

    const {
      hideSuggestions,
      suggestionGroups: suggestions,
      activeSuggestion,
      setActiveSuggestion,
      suggestionsVisible,
      suggestionSelected,
      updateSuggestions,
    } = useSuggestions()
    const {forceReparse, onSubmit, rawFilterRef, updateFilter} = useFilterQuery()
    const {config} = useFilter()

    const updateInputSelection = useCallback((selectionStart: number, selectionEnd?: number | null) => {
      setInputSelectionStart(selectionStart)
      setInputSelectionEnd(selectionEnd ?? selectionStart)
    }, [])

    useImperativeHandle(ref, () => ({
      caretStart: inputSelectionStart,
      caretEnd: inputSelectionEnd,
      isComposing: isComposing.current,
      inputHasFocus: isInputFocused,
      styledInputBlockCount: styledInputBlockCount.current,
      updateCaretPosition: updateInputSelection,
      updateRawFilterValue,
    }))

    const inputKeyDown = useCallback(
      (event: React.KeyboardEvent<HTMLInputElement>) => {
        if (isComposing.current) return

        const flatSuggestions = getFlatSuggestionsList(suggestions)

        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
          hideSuggestions()
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        } else if (event.key === 'ArrowDown') {
          if (activeSuggestion + 1 >= flatSuggestions.length) {
            setActiveSuggestion(-1)
          } else {
            setActiveSuggestion(activeSuggestion + 1)
          }
          event.preventDefault()
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        } else if (event.key === 'ArrowUp') {
          // If the current suggestion is the top of the list, then move to the end
          if (activeSuggestion < 0) {
            setActiveSuggestion(flatSuggestions.length - 1)
          } else {
            setActiveSuggestion(activeSuggestion - 1)
          }
          event.preventDefault()
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        } else if (event.key === 'Enter') {
          if (suggestionsVisible && activeSuggestion !== null) {
            const suggestion = flatSuggestions[activeSuggestion]
            if (suggestion) {
              event.preventDefault()
              suggestionSelected(suggestion)
              inputRef.current?.focus()
            } else {
              onSubmit(SubmitEvent.ExplicitSubmit, 'input_with_enter')
            }
          } else {
            onSubmit(SubmitEvent.ExplicitSubmit, 'input_with_enter')
          }
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        } else if (event.key === 'Escape') {
          hideSuggestions()
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        } else if (event.key === 'Home' || event.key === 'End') {
          setActiveSuggestion(-1)
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        } else if ((filterConfig.groupAndKeywordSupport && ['('].includes(event.key)) || event.key === '"') {
          const input = event.currentTarget
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
          const keyPressed = event.key

          // If there is a selection, and the user types a wrapping character, surround the selection
          if (input.selectionStart !== input.selectionEnd && ['(', '"'].includes(keyPressed)) {
            const closing = keyPressed === '(' ? ')' : '"'
            const wrappedValue = `${input.value.slice(0, inputSelectionStart)}${keyPressed}${input.value.slice(
              inputSelectionStart,
              inputSelectionEnd,
            )}${closing}${input.value.slice(inputSelectionEnd)}`
            // Set the selection to around the wrapped value, but excluding the inserted characters
            updateNativeInputElement(input, wrappedValue, inputSelectionStart + 1, inputSelectionEnd + 1)

            event.preventDefault() // Prevent original keystroke
            return
          }

          const caretIndex = input.selectionEnd ?? input.selectionStart ?? -1

          // If the user types a closing quote before one that is already present, don't insert a new one
          if (keyPressed === '"' && input.value.charAt(caretIndex) === '"') {
            updateNativeInputElement(input, input.value, inputSelectionStart + 1)
            event.preventDefault() // Prevent original keystroke
            return
          }

          // Disable auto close before closing character and before or after a word character

          if (input.value.charAt(caretIndex).match(/\w/g) || input.value.charAt(caretIndex - 1).match(/[\w"]/g)) return

          if (keyPressed === '(') {
            const matchedQuotes = findMatchedQuotes(input.value)
            for (const [openQuoteIndex, closeQuoteIndex] of matchedQuotes) {
              if (caretIndex > openQuoteIndex && caretIndex <= closeQuoteIndex) {
                // Do not auto close when inside quotations for filter value
                return
              }
            }
          }
          event.preventDefault() // Prevent original keystroke

          const closing = keyPressed === '(' ? ')' : '"'
          const autoClosedValue = `${input.value.slice(0, caretIndex)}${keyPressed}${closing}${input.value.slice(
            caretIndex,
          )}`

          updateNativeInputElement(input, autoClosedValue, caretIndex + 1)
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        } else if (event.key === 'Backspace') {
          const input = event.currentTarget
          const caretIndex = input.selectionEnd ?? -1
          if (
            (filterConfig.groupAndKeywordSupport &&
              input.value.charAt(caretIndex - 1) === '(' &&
              input.value.charAt(caretIndex) === ')') ||
            (input.value.charAt(caretIndex - 1) === '"' && input.value.charAt(caretIndex) === '"')
          ) {
            event.preventDefault()
            const newValue = `${input.value.slice(0, caretIndex - 1)}${input.value.slice(caretIndex + 1)}`
            updateNativeInputElement(input, newValue, caretIndex - 1)
          }
        }
      },
      [
        activeSuggestion,
        filterConfig.groupAndKeywordSupport,
        hideSuggestions,
        inputSelectionEnd,
        inputSelectionStart,
        onSubmit,
        setActiveSuggestion,
        suggestionSelected,
        suggestions,
        suggestionsVisible,
      ],
    )

    const inputOnFocus = useCallback(() => {
      setIsInputFocused(true)
      if (isInteractingWithSuggestions) {
        setIsInteractingWithSuggestions(false)
      } else {
        forceReparse(-1, async query => {
          if (checkFilterQuerySync(query, rawFilterRef?.current)) await updateSuggestions(query, inputSelectionStart)
        })
      }
    }, [isInteractingWithSuggestions, forceReparse, rawFilterRef, updateSuggestions, inputSelectionStart])

    const inputOnBlur = useCallback(() => {
      if (isInteractingWithSuggestions) {
        return
      }
      setIsInputFocused(false)
      forceReparse(-1)
      hideSuggestions()
    }, [isInteractingWithSuggestions, forceReparse, hideSuggestions])

    // Input composition events for use with IME keyboards (e.g. Japanese, Chinese character composition)
    const inputOnCompositionStart: React.CompositionEventHandler = useCallback(() => {
      isComposing.current = true
      hideSuggestions()
    }, [hideSuggestions])

    const inputOnCompositionEnd: React.CompositionEventHandler = useCallback(() => {
      isComposing.current = false
    }, [])

    const inputOnChange = useCallback<React.ChangeEventHandler<HTMLInputElement>>(
      e => {
        const input = e.currentTarget
        const currentValue = input.value

        // Prevent the input from getting into an infinite loop
        if (currentValue === filterValue) return

        setFilterValue(currentValue)

        e.preventDefault()
        const caretStartIndex = config.variant !== 'button' ? input.selectionStart ?? -1 : -1
        const caretEndIndex = config.variant !== 'button' ? input.selectionEnd ?? -1 : -1

        updateFilter(currentValue, caretStartIndex, query => {
          void updateSuggestions(query, caretStartIndex)
        })

        updateInputSelection(caretStartIndex, caretEndIndex)
      },
      [config.variant, updateFilter, updateInputSelection, updateSuggestions, filterValue],
    )

    const updateRawFilterValue = useCallback(
      (value: string) => {
        if (value === filterValue) return

        setFilterValue(value)
        updateFilter(value, -1)
      },
      [filterValue, updateFilter],
    )

    const updateStyledInputBlockCount = useCallback((count: number) => {
      styledInputBlockCount.current = count
    }, [])

    const suspendFocus = useCallback(() => {
      setIsInteractingWithSuggestions(true)
    }, [])

    const inputContextValue = useMemo<InputContext>(
      () => ({
        caretRef,
        inputFocused: isInputFocused,
        inputKeyDown,
        inputOnBlur,
        inputOnCompositionStart,
        inputOnCompositionEnd,
        inputOnChange,
        inputOnFocus,
        inputRef,
        inputSelectionEnd,
        inputSelectionStart,
        inputValue: filterValue,
        suspendFocus,
        updateInputSelection,
        updateStyledInputBlockCount,
      }),
      [
        isInputFocused,
        inputKeyDown,
        inputOnBlur,
        inputOnCompositionStart,
        inputOnCompositionEnd,
        inputOnChange,
        inputOnFocus,
        inputSelectionEnd,
        inputSelectionStart,
        filterValue,
        suspendFocus,
        updateInputSelection,
        updateStyledInputBlockCount,
      ],
    )

    return <InputContext.Provider value={inputContextValue}>{children}</InputContext.Provider>
  },
)

InputContextProvider.displayName = 'InputContextProvider'
