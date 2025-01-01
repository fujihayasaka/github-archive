import {Dialog} from '@primer/react/experimental'

import {FormControl, Textarea} from '@primer/react'
import {testIdProps} from '@github-ui/test-id-props'
import type {ImprovePromptDialogState, Prompt} from '../../../types'
import {sendEvent} from '@github-ui/hydro-analytics'
import {GenerateSystemPromptClicked, GenerateUserPromptClicked} from '../../../utils/playground-types'

interface ImprovePromptDialogProps {
  onClose: () => void
  setDialogState: (status: ImprovePromptDialogState) => void
  currentPrompt: string
  setCurrentPrompt: (text: string) => void
  promptSuggestionText: string
  setPromptSuggestionText: (text: string) => void
  type: Prompt
}

export function ImprovePromptDialog({
  onClose,
  setDialogState,
  currentPrompt,
  setCurrentPrompt,
  promptSuggestionText,
  setPromptSuggestionText,
  type,
}: ImprovePromptDialogProps) {
  const handleGeneratePrompt = () => {
    setDialogState('confirm')
    if (type === 'user') {
      sendEvent(GenerateUserPromptClicked)
    } else {
      sendEvent(GenerateSystemPromptClicked)
    }
  }

  return (
    <Dialog
      width="large"
      onClose={onClose}
      title={<div {...testIdProps('prompt-dialog')}>Improve prompt</div>}
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: onClose,
        },
        {
          buttonType: 'primary',
          content: 'Improve prompt',
          disabled: currentPrompt.length === 0,
          onClick: handleGeneratePrompt,
        },
      ]}
    >
      Adjust your prompt with specific suggestions or simply click to enhance your prompt.
      <div className="py-3 d-flex flex-column gap-3">
        <FormControl>
          <FormControl.Label>Current prompt</FormControl.Label>
          <Textarea value={currentPrompt} className="width-full" onChange={e => setCurrentPrompt(e.target.value)} />
        </FormControl>
        <FormControl>
          <FormControl.Label>What would you like to improve? (optional)</FormControl.Label>
          <Textarea
            placeholder="Eg: explain X for a beginner and write responses in nested bullets."
            value={promptSuggestionText}
            onChange={e => setPromptSuggestionText(e.target.value)}
            className="width-full"
          />
        </FormControl>
      </div>
    </Dialog>
  )
}
