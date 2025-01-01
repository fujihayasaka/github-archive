import {FormControl, TextInput} from '@primer/react'
import {LABELS} from './constants/labels'
import {Suspense} from 'react'
import {EmojiAutocomplete} from '@github-ui/emoji-autocomplete'
import styles from './CreateIssueFormTitle.module.css'

type CreateIssueFormTitleProps = {
  title: string
  titleInputRef: React.RefObject<HTMLInputElement>
  handleTitleChange: (event: React.ChangeEvent<HTMLInputElement>) => void
  titleValidationResult?: string | null
  emojiTone?: number
}

export const CreateIssueFormTitle = ({
  title,
  titleValidationResult,
  titleInputRef,
  handleTitleChange,
  emojiTone,
}: CreateIssueFormTitleProps) => {
  const textInput = (
    <TextInput
      ref={titleInputRef}
      aria-label={LABELS.issueCreateTitleLabel}
      placeholder={LABELS.issueCreateTitlePlaceholder}
      aria-describedby="issue-create-pane-title title-validation"
      value={title}
      onChange={handleTitleChange}
      onInput={handleTitleChange}
      data-hpc
      autoFocus
      data-react-autofocus
    />
  )

  return (
    <div className={styles.container}>
      <FormControl className={styles.formControl} required>
        <FormControl.Label className={styles.formControlLabel}>{LABELS.issueCreateTitleLabel}</FormControl.Label>
        <div className={styles.subcontainer}>
          <Suspense fallback={textInput}>
            <EmojiAutocomplete tone={emojiTone}>{textInput}</EmojiAutocomplete>
          </Suspense>
          {titleValidationResult && (
            <span role="alert" aria-live="assertive">
              <FormControl.Validation variant="error" id="title-validation">
                {titleValidationResult}
              </FormControl.Validation>
            </span>
          )}
        </div>
      </FormControl>
    </div>
  )
}
