import {useEffect} from 'react'
import {Dialog, FormControl, IconButton, Spinner, Textarea} from '@primer/react'
import {testIdProps} from '@github-ui/test-id-props'
import type {Model} from '@github-ui/marketplace-common'
import {useModelClient} from '../contexts/ModelClientContext'
import {useImprovePrompt} from '../hooks/use-improve-prompt'
import {ArrowLeftIcon} from '@primer/octicons-react'
import type {ImprovePromptDialogState, Prompt} from '../../../types'

interface ImprovePromptConfirmationDialogProps {
  setDialogState: (status: ImprovePromptDialogState) => void
  onClose: () => void
  handleUpdatePrompt: () => void
  promptSuggestionText: string
  currentPrompt: string
  setImprovedPromptText: (value: string) => void
  improvedPromptText: string
  improvedPromptModel: Model
  type: Prompt
}

export function ImprovePromptConfirmationDialog({
  setDialogState,
  onClose,
  handleUpdatePrompt,
  promptSuggestionText,
  currentPrompt,
  setImprovedPromptText,
  improvedPromptText,
  improvedPromptModel,
  type,
}: ImprovePromptConfirmationDialogProps) {
  const modelClient = useModelClient()

  const {generatedPrompt, isLoading} = useImprovePrompt(
    currentPrompt,
    promptSuggestionText,
    modelClient,
    improvedPromptModel,
    type,
  )

  useEffect(() => {
    setImprovedPromptText(generatedPrompt)
  }, [generatedPrompt, setImprovedPromptText])

  return (
    <Dialog
      width="large"
      onClose={onClose}
      title={
        <div {...testIdProps('prompt-dialog-confirmation')} className="d-flex flex-items-center">
          <IconButton
            icon={ArrowLeftIcon}
            aria-label="Back"
            variant="invisible"
            className="mr-2"
            onClick={() => {
              setDialogState('suggest')
            }}
          />
          Improve prompt
        </div>
      }
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: onClose,
        },
        {
          buttonType: 'primary',
          content: 'Use improved prompt',
          onClick: handleUpdatePrompt,
        },
      ]}
    >
      Apply the improved prompt or return to previous dialog for additional iterations.
      <div className="py-3 d-flex flex-column gap-3">
        <FormControl>
          <FormControl.Label className="d-flex flex-items-center gap-2">
            Improved prompt
            {isLoading && <Spinner size="small" srText="Loading improved prompt" />}
          </FormControl.Label>

          <Textarea
            value={improvedPromptText}
            onChange={e => setImprovedPromptText(e.target.value)}
            className="width-full"
          />
        </FormControl>
      </div>
      <span className="color-fg-muted text-small">This tool uses AI. Check for mistakes.</span>
    </Dialog>
  )
}
