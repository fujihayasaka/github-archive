import {testIdProps} from '@github-ui/test-id-props'
import {forwardRef, useCallback} from 'react'

import {Resources} from '../../strings'
import {AutosizeTextInput} from '../common/autosize-text-input'
import {BorderlessTextInput} from '../common/borderless-text-input'
import styles from './raw-filter-input.module.css'

interface RawFilterInputProps
  extends React.DetailedHTMLProps<React.InputHTMLAttributes<HTMLInputElement>, HTMLInputElement> {
  /**
   * Whether or not we're currently showing filter suggestions - used for aria expanded state
   */
  areFilterSuggestionsVisible: boolean
}

function stopEvent(e: React.MouseEvent<HTMLInputElement>) {
  e.stopPropagation()
  e.preventDefault()
}

export const FILTER_INPUT_LIST_ID = 'search-suggestions-box'
export const FILTER_BAR_INPUT_ID = 'filter-bar-input'

export const RawFilterInput = forwardRef<HTMLInputElement, RawFilterInputProps>(function RawFilterInput(
  {areFilterSuggestionsVisible, value, onChange, onKeyDown, onFocus, onBlur, onClick, disabled, ...props},
  forwardedRef,
) {
  const handleClick: React.MouseEventHandler<HTMLInputElement> = useCallback(
    e => {
      stopEvent(e)
      onClick?.(e)
    },
    [onClick],
  )
  return (
    <AutosizeTextInput
      as={BorderlessTextInput}
      role="combobox"
      id={FILTER_BAR_INPUT_ID}
      aria-haspopup="listbox"
      aria-expanded={areFilterSuggestionsVisible}
      aria-autocomplete="list"
      aria-controls={FILTER_INPUT_LIST_ID}
      aria-label={Resources.filterByKeyboardOrByField}
      name="Filter"
      value={value}
      disabled={disabled}
      onChange={onChange}
      onClick={handleClick}
      onKeyDown={onKeyDown}
      onFocus={onFocus}
      onBlur={onBlur}
      placeholder={Resources.filterByKeyboardOrByField}
      autoComplete="off"
      autoCorrect="false"
      autoCapitalize="false"
      spellCheck="false"
      {...testIdProps('filter-bar-input')}
      ref={forwardedRef}
      tabIndex={0}
      className={styles.AutosizeTextInput}
      containerClassName={styles.AutosizeTextInput_1}
      {...props}
    />
  )
})
