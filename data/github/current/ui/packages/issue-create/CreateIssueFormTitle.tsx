import {Box, FormControl, TextInput} from '@primer/react'
import {LABELS} from './constants/labels'
import {Suspense} from 'react'
import {EmojiAutocomplete} from '@github-ui/emoji-autocomplete'

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
      value={title}
      onBlur={handleTitleChange}
      onChange={handleTitleChange}
      data-hpc
    />
  )

  return (
    <Box sx={{display: 'flex', alignItems: 'center'}}>
      <FormControl sx={{display: 'flex', flexDirection: 'column', alignItems: 'stretch', flex: 1}} required>
        <FormControl.Label
          sx={{'> span > span:last-of-type': {color: 'var(--fgColor-danger, var(--color-danger-fg))'}}}
        >
          {LABELS.issueCreateTitleLabel}
        </FormControl.Label>
        <Box sx={{display: 'flex', flexDirection: 'column', flex: 1, mr: 2}}>
          <Suspense fallback={textInput}>
            <EmojiAutocomplete tone={emojiTone}>{textInput}</EmojiAutocomplete>
          </Suspense>
          {titleValidationResult && (
            <FormControl.Validation variant="error">{titleValidationResult}</FormControl.Validation>
          )}
        </Box>
      </FormControl>
    </Box>
  )
}
