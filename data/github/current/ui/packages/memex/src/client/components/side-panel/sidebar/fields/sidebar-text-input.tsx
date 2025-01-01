import {PointerBox} from '@primer/react'
import {type KeyboardEventHandler, useCallback, useEffect, useRef, useState} from 'react'

import {BorderlessTextInput} from '../../../common/borderless-text-input'
import {EmojiAutocomplete} from '../../../common/emoji-autocomplete'
import {FieldValue} from './core'

export const SidebarTextInput = ({
  submitValue,
  defaultValue,
  validationFn,
  type = 'text',
  withEmojiPicker = false,
  placeholder,
  onKeyDown,
}: {
  submitValue: (newValue: string) => void
  defaultValue: string
  validationFn?: (newValue: string) => string | undefined
  withEmojiPicker?: boolean
  type?: 'text' | 'date'
  placeholder: string
  onKeyDown?: KeyboardEventHandler
}) => {
  const inputRef = useRef<HTMLInputElement>(null)
  const [invalidMessage, setInvalidMessage] = useState<string | undefined>(undefined)
  const [value, setValue] = useState(defaultValue)
  useEffect(() => {
    if (inputRef.current && inputRef.current === document.activeElement) return
    setValue(defaultValue)
  }, [defaultValue])
  // Updates validation message state and returns true if valid
  const validate = (newValue: string): boolean => {
    const message = validationFn?.(newValue)
    setInvalidMessage(message)
    return !message
  }

  const handleSubmitValue = (newValue: string) => {
    if (validate(newValue)) {
      submitValue(newValue)
    }
  }

  const resetValue = useCallback(() => setValue(defaultValue), [defaultValue])

  const handleKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if (event.key === 'Enter') {
      event.preventDefault()
      handleSubmitValue(value)
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    } else if (event.key === 'Escape') {
      event.preventDefault()
      event.stopPropagation()
      resetValue()
    }

    onKeyDown?.(event)
  }

  const onChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = event.currentTarget.value
    setValue(newValue)
    validate(newValue)
  }

  const onBlur = () => {
    if (value !== defaultValue && validate(value)) {
      submitValue(value)
    } else {
      resetValue()
    }
  }

  const input = (
    <FieldValue
      interactable
      as={BorderlessTextInput}
      ref={inputRef}
      onBlur={onBlur}
      onChange={onChange}
      onKeyDown={handleKeyDown}
      type={type}
      value={value}
      placeholder={placeholder}
      aria-label="Edit value"
    />
  )

  return (
    <>
      {withEmojiPicker ? <EmojiAutocomplete fullWidth>{input}</EmojiAutocomplete> : input}
      {invalidMessage ? (
        <PointerBox
          sx={{
            position: 'absolute',
            zIndex: 100,
            fontSize: 0,
            mt: '12px',
            py: 1,
            px: 2,
            bg: 'danger.subtle',
            color: 'fg.default',
            borderColor: 'danger.muted',
          }}
          caret="top-left"
        >
          <span>{invalidMessage}</span>
        </PointerBox>
      ) : null}
    </>
  )
}
