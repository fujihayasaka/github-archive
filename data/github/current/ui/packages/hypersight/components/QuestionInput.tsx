import {PaperAirplaneIcon} from '@primer/octicons-react'
import {FormControl, IconButton, Spinner} from '@primer/react'
import {useCallback, useState} from 'react'
import styles from './QuestionInput.module.css'

type QuestionInputProps = {
  isAnswering: boolean
  onSubmit: (question: string) => void
}

export function QuestionInput({isAnswering, onSubmit}: QuestionInputProps) {
  const [inputValue, setInputValue] = useState('')
  const handleSubmit = useCallback(() => {
    const value = inputValue.trim()
    setInputValue('')
    onSubmit(value)
  }, [inputValue, onSubmit])

  return (
    <>
      <form>
        <FormControl className={styles.formContainer}>
          <FormControl.Label visuallyHidden>Followup question</FormControl.Label>
          <div className={styles.inputGroup}>
            {isAnswering ? (
              <div className={styles.leadingActions}>
                <Spinner size="small" srText="Loading" />
              </div>
            ) : null}

            <input
              value={inputValue}
              disabled={isAnswering}
              onChange={e => setInputValue(e.target.value)}
              className={styles.textInput}
              placeholder={
                isAnswering
                  ? 'Responding'
                  : 'Ask a follow up question about this pull request or the broader codebase...'
              }
            />
            {isAnswering ? null : (
              <div className={styles.trailingActions}>
                <IconButton
                  type="submit"
                  variant="invisible"
                  icon={PaperAirplaneIcon}
                  onClick={handleSubmit}
                  aria-label="Send"
                  disabled={!inputValue}
                />
              </div>
            )}
          </div>
        </FormControl>
      </form>
    </>
  )
}
