import {testIdProps} from '@github-ui/test-id-props'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {clsx} from 'clsx'
import type React from 'react'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {MIN_INPUT_WIDTH} from '../constants/defaults'
import {useInput, useSuggestions} from '../context'
import styles from './Input.module.css'
import {StyledInput} from './StyledInput'

type FilterInputProps = {
  id: string
  hasValidationMessage?: boolean
  placeholder?: string
  onKeyDown?: React.KeyboardEventHandler
}

export const Input = ({
  id,
  hasValidationMessage = false,
  placeholder = 'Search or filter',
  onKeyDown,
}: FilterInputProps) => {
  const {suggestionsVisible, activeSuggestion, suggestionGroups} = useSuggestions()
  const {
    caretRef,
    inputFocused,
    inputKeyDown,
    inputOnBlur,
    inputOnCompositionStart,
    inputOnCompositionEnd,
    inputOnChange,
    inputOnFocus,
    inputRef,
    inputSelectionEnd,
    inputSelectionStart,
    inputValue,
    updateInputSelection,
  } = useInput()
  const sizerRef = useRef<HTMLDivElement>(null)
  const [inputScrollLeft, setInputScrollLeft] = useState(0)
  const styledInputContainerRef = useRef<HTMLDivElement>(null)

  const checkCursorPosition = useCallback(
    (el: HTMLInputElement) => {
      updateInputSelection(el.selectionStart ?? 0, el.selectionEnd ?? 0)
    },
    [updateInputSelection],
  )

  const onKeyDownHandler = useCallback<React.KeyboardEventHandler<HTMLInputElement>>(
    e => {
      checkCursorPosition(e.currentTarget as HTMLInputElement)
      inputKeyDown(e)
      onKeyDown?.(e)
    },
    [checkCursorPosition, inputKeyDown, onKeyDown],
  )

  const onClickHandler = useCallback<React.MouseEventHandler<HTMLInputElement>>(
    e => {
      checkCursorPosition(e.currentTarget as HTMLInputElement)
    },
    [checkCursorPosition],
  )

  const inputWidth = useMemo(() => {
    const currentSizerScrollWidth = sizerRef.current?.scrollWidth ?? 0
    const newInputWidth = Math.max(currentSizerScrollWidth + 2, MIN_INPUT_WIDTH)

    return `${newInputWidth}px`

    // This adds a subscriptions to recalculate in the event of state changes that impact the input width
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [inputSelectionStart, sizerRef.current?.scrollWidth, inputValue])

  useLayoutEffect(() => {
    const cursor = caretRef.current
    const styledInputContainer = styledInputContainerRef.current

    if (cursor && styledInputContainer) {
      //If the cursor is out of view to the left
      if (cursor.offsetLeft < inputScrollLeft) {
        setInputScrollLeft(cursor.offsetLeft - styledInputContainer.clientWidth - MIN_INPUT_WIDTH)
        //If the cursor is out of view to the right
      } else if (cursor.offsetLeft > inputScrollLeft + styledInputContainer.clientWidth) {
        setInputScrollLeft(cursor.offsetLeft - styledInputContainer.clientWidth + MIN_INPUT_WIDTH)
      } else {
        styledInputContainer.scrollLeft = inputScrollLeft
      }
    }
  }, [caretRef, inputScrollLeft, inputSelectionStart, inputValue])

  const shadowInput = useMemo(() => {
    return (
      <>
        <span>{inputSelectionStart ? inputValue.substring(0, inputSelectionStart) : inputValue}</span>
        <span {...testIdProps('filter-cursor')} ref={caretRef} />
        <span>{inputSelectionStart ? inputValue.substring(inputSelectionStart) : null}</span>
      </>
    )
  }, [caretRef, inputSelectionStart, inputValue])

  const ariaExpandedValue = useMemo(() => {
    return suggestionsVisible && suggestionGroups.some(s => s.suggestions.length > 0)
  }, [suggestionGroups, suggestionsVisible])

  useEffect(() => {
    if (inputRef.current && inputSelectionStart > -1 && inputFocused) {
      inputRef.current.selectionStart = inputSelectionStart
      inputRef.current.selectionEnd = inputSelectionEnd
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [inputRef, inputSelectionStart, inputSelectionEnd, inputValue])

  return (
    <div
      {...testIdProps('styled-input-container')}
      ref={styledInputContainerRef}
      tabIndex={-1}
      className={clsx('styled-input-container', styles.Box_0)}
    >
      <div
        {...testIdProps('styled-input-content')}
        aria-hidden="true"
        className={clsx('styled-input-content', styles.Box_1)}
      >
        {/* This is a visual-only component and is intentionally hidden from screen readers.
        It will use the Input below instead */}
        <StyledInput />
      </div>
      <div {...testIdProps('filter-input-wrapper')} className={styles.Box_2}>
        <div {...testIdProps('filter-sizer')} ref={sizerRef} aria-hidden="true" className={styles.Box_3}>
          {shadowInput}
        </div>
        <input
          id={`${id}-input`}
          role="combobox"
          aria-expanded={ariaExpandedValue}
          aria-autocomplete="list"
          aria-haspopup="listbox"
          aria-controls={`${id}-results`}
          aria-activedescendant={
            activeSuggestion !== null && activeSuggestion !== -1 && suggestionsVisible
              ? `suggestion-${activeSuggestion}`
              : undefined
          }
          aria-describedby={hasValidationMessage ? `${id}-validation-message` : ''}
          placeholder={placeholder}
          ref={inputRef}
          value={inputValue}
          onFocus={inputOnFocus}
          onBlur={inputOnBlur}
          onCompositionStart={inputOnCompositionStart}
          onCompositionEnd={inputOnCompositionEnd}
          onKeyDown={onKeyDownHandler}
          onClick={onClickHandler}
          onChange={inputOnChange}
          name={`${id}-inputname`}
          autoComplete="off"
          spellCheck="false"
          style={{width: inputWidth}}
          className={styles.Box_4}
          {...testIdProps('filter-input')}
        />
      </div>
    </div>
  )
}
