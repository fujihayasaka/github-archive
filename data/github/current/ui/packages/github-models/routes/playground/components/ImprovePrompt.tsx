import {useCallback, useState} from 'react'
import type {ImprovePromptDialogState, Prompt, ShowModelPayload} from '../../../types'
import {ImprovePromptDialog} from './ImprovePromptDialog'
import {ImprovePromptConfirmationDialog} from './ImprovePromptConfirmationDialog'
import {sendEvent} from '@github-ui/hydro-analytics'
import {
  CancelImprovedSystemPromptClicked,
  CancelImprovedUserPromptClicked,
  ImproveSystemPromptClicked,
  ImproveUserPromptClicked,
  UseImprovedSystemPromptClicked,
  UseImprovedUserPromptClicked,
} from '../../../utils/playground-types'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Button, IconButton} from '@primer/react'
import {SparkleFillIcon, SparklesFillIcon} from '@primer/octicons-react'

export type ImprovePromptProps = {
  prompt: string
  handleUpdatePrompt: (improvedPrompt: string) => void
  type?: Prompt
}

export function ImprovePrompt({prompt, handleUpdatePrompt, type = 'system'}: ImprovePromptProps) {
  const {improvedPromptModel} = useRoutePayload<ShowModelPayload>()

  const [dialogState, setDialogState] = useState<ImprovePromptDialogState>('closed')

  const [promptSuggestionText, setPromptSuggestionText] = useState('')
  const [improvedPromptText, setImprovedPromptText] = useState('')

  const onOpen = useCallback(() => {
    setDialogState('suggest')
    if (type === 'user') {
      sendEvent(ImproveUserPromptClicked)
    } else {
      sendEvent(ImproveSystemPromptClicked)
    }
  }, [type])

  const onClose = useCallback(() => {
    setDialogState('closed')
  }, [])

  const onCloseConfirmationDialog = useCallback(() => {
    setDialogState('closed')
    if (type === 'user') {
      sendEvent(CancelImprovedUserPromptClicked)
    } else {
      sendEvent(CancelImprovedSystemPromptClicked)
    }
  }, [type])

  const handleUpdate = useCallback(() => {
    handleUpdatePrompt(improvedPromptText)
    setPromptSuggestionText('')
    setDialogState('closed')
    if (type === 'user') {
      sendEvent(UseImprovedUserPromptClicked)
    } else {
      sendEvent(UseImprovedSystemPromptClicked)
    }
  }, [handleUpdatePrompt, improvedPromptText, type])

  if (!improvedPromptModel) {
    return null
  }

  return (
    <>
      {type === 'system' ? (
        <Button onClick={onOpen} variant="invisible" size="small">
          <div className="d-flex flex-items-center gap-1">
            <SparklesFillIcon />
            <span>Improve prompt</span>
          </div>
        </Button>
      ) : (
        <IconButton
          variant="invisible"
          size="small"
          icon={SparkleFillIcon}
          onClick={onOpen}
          aria-label="Open improve prompt dialog"
        />
      )}
      {dialogState === 'suggest' && (
        <ImprovePromptDialog
          onClose={onClose}
          setDialogState={setDialogState}
          currentPrompt={prompt}
          setCurrentPrompt={handleUpdatePrompt}
          promptSuggestionText={promptSuggestionText}
          setPromptSuggestionText={setPromptSuggestionText}
          type={type}
        />
      )}
      {dialogState === 'confirm' && (
        <ImprovePromptConfirmationDialog
          onClose={onCloseConfirmationDialog}
          handleUpdatePrompt={handleUpdate}
          promptSuggestionText={promptSuggestionText}
          currentPrompt={prompt}
          setImprovedPromptText={setImprovedPromptText}
          improvedPromptText={improvedPromptText}
          improvedPromptModel={improvedPromptModel}
          setDialogState={setDialogState}
          type={type}
        />
      )}
    </>
  )
}
