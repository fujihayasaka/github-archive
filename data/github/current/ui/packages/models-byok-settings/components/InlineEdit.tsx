import {CheckIcon, PencilIcon, XIcon} from '@primer/octicons-react'
import {IconButton, Stack, TextInput, useOnEscapePress} from '@primer/react'
import {
  type KeyboardEventHandler,
  type PropsWithChildren,
  type RefObject,
  startTransition,
  useCallback,
  useEffect,
  useRef,
  useState,
} from 'react'

import styles from './InlineEdit.module.css'

/*
NOTE; This component has not been built as a general-purpose inline edit solution,
it may work for your use-case, and if so, great. It was built for the ModelSelector
*/
export function InlineEdit({
  'aria-describedby': ariaDescribedby,
  children,
  defaultValue,
  enabled,
  onSave,
  returnFocusRef,
}: PropsWithChildren<{
  'aria-describedby'?: string
  defaultValue?: string
  enabled: boolean
  onSave?: (newValue: string) => void
  returnFocusRef?: RefObject<HTMLElement>
}>) {
  const [editing, setEditing] = useState(false)

  const inputRef = useRef<HTMLInputElement>(null)

  const returnFocus = useCallback(() => {
    globalThis.requestAnimationFrame(() => {
      returnFocusRef?.current?.focus()
    })
  }, [returnFocusRef])

  // If we edit, select the input so the user can start typing
  useEffect(() => {
    if (editing && inputRef.current) {
      globalThis.requestAnimationFrame(() => {
        inputRef.current?.select()
      })
    }
  }, [editing])

  const cancel = useCallback(() => {
    setEditing(false)
    returnFocus()
  }, [returnFocus])

  useOnEscapePress(
    (event: KeyboardEvent) => {
      if (editing && event.target === inputRef.current) {
        event.preventDefault()
        cancel()
      }
    },
    [editing, returnFocus, cancel],
  )

  const save = useCallback(() => {
    if (!inputRef.current || !onSave) return void cancel()
    const newValue = inputRef.current.value
    startTransition(() => {
      onSave(newValue)
      returnFocus()
      setEditing(false)
    })
  }, [onSave, cancel, returnFocus])

  const handleEnter = useCallback<KeyboardEventHandler<HTMLInputElement>>(
    event => {
      if (event.target !== inputRef.current) return

      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (event.key === 'Enter') {
        event.preventDefault()
        save()
      }
    },
    [save],
  )

  if (!enabled) return <>{children}</>

  return (
    <Stack align="center" direction="horizontal" gap="condensed">
      {editing ? (
        <TextInput
          ref={inputRef}
          defaultValue={defaultValue}
          size="small"
          className="width-full"
          aria-label="Edit value"
          aria-describedby={ariaDescribedby}
          onKeyDown={handleEnter}
        />
      ) : (
        children
      )}
      <div className={styles.ActionsContainer}>
        {editing && (
          <>
            <IconButton
              icon={XIcon}
              variant="default"
              size="small"
              aria-label="Cancel edit"
              aria-describedby={ariaDescribedby}
              onClick={cancel}
            />
            <IconButton
              icon={CheckIcon}
              variant="default"
              size="small"
              aria-label="Save edits"
              aria-describedby={ariaDescribedby}
              onClick={save}
            />
          </>
        )}
        {!editing && (
          <IconButton
            icon={PencilIcon}
            variant="invisible"
            size="small"
            aria-label="Edit"
            aria-describedby={ariaDescribedby}
            onClick={() => setEditing(true)}
          />
        )}
      </div>
    </Stack>
  )
}
