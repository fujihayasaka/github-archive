import {PaperAirplaneIcon} from '@primer/octicons-react'
import {FormControl, TextInput, IconButton, Spinner} from '@primer/react'
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
          <TextInput
            value={inputValue}
            disabled={isAnswering}
            onChange={e => setInputValue(e.target.value)}
            placeholder={
              isAnswering ? 'Responding' : 'Ask a follow up question about this pull request or the broader codebase...'
            }
            block
            size="large"
            leadingVisual={() => (isAnswering ? <Spinner size="small" /> : null)}
            trailingVisual={() =>
              isAnswering ? null : (
                <IconButton
                  type="submit"
                  icon={PaperAirplaneIcon}
                  onClick={handleSubmit}
                  aria-label="Send"
                  disabled={!inputValue}
                />
              )
            }
            className={styles.textInput}
          />
        </FormControl>
      </form>
    </>
  )
}
