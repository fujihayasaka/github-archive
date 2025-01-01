import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {CustomCopilotFreeTextResource} from '@github-ui/custom-copilots/types'
import {ScopedCommands} from '@github-ui/ui-commands'
import {Dialog, FormControl, Stack, Textarea, TextInput} from '@primer/react'
import type React from 'react'
import {useState} from 'react'

import {useUpsertCopilotSpace} from './hooks/use-upsert-copilot-space'

interface TextFileDialogProps {
  onClose: () => void
  copilotSpaceId: CustomCopilot['id']
  resource?: CustomCopilotFreeTextResource
  // saveResource: (resource: CustomCopilotFreeTextResource) => Promise<Response>
}

const FILE_NAME_MAX_LENGTH = 1_000
const FILE_TEXT_MAX_LENGTH = 20_000

export function TextFileDialog({onClose, copilotSpaceId, resource}: TextFileDialogProps) {
  const [name, setName] = useState(resource?.name ?? '')
  const [text, setText] = useState(resource?.text ?? '')

  const [errorMessages, setErrorMessages] = useState<Record<string, string>>({})

  const {upsertCopilotSpace, isPending} = useUpsertCopilotSpace(copilotSpaceId)

  const handleSubmit = async (e?: React.FormEvent): Promise<void> => {
    e?.preventDefault()

    // Prevents double saving
    if (isPending) return

    try {
      await upsertCopilotSpace({
        resources: [
          {
            id: Date.now().toString(),
            type: 'free_text',
            name,
            text,
            markedForDestroy: false,
            ...(resource && {
              id: resource.id,
              databaseId: resource.databaseId,
            }),
          },
        ],
      })
      onClose()
    } catch (errors) {
      setErrorMessages(errors as Record<string, string>)
    }
  }

  const isEdit = Boolean(resource)

  return (
    <Dialog
      width="large"
      title={isEdit ? 'Edit a text file' : 'Add a text file'}
      onClose={onClose}
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: onClose,
        },
        {
          buttonType: 'primary',
          content: isEdit ? 'Save' : 'Add',
          onClick: () => void handleSubmit(),
          loading: isPending,
          loadingAnnouncement: 'Saving resource',
        },
      ]}
    >
      <ScopedCommands commands={{'github:submit-form': void handleSubmit}}>
        <form onSubmit={handleSubmit}>
          <Stack>
            <FormControl required>
              <FormControl.Label>Name</FormControl.Label>
              <TextInput
                block
                placeholder="Give the file a title"
                value={name}
                onChange={e => {
                  setName(e.target.value)
                  setErrorMessages(prev => ({...prev, 'resources.name': ''}))
                }}
                maxLength={FILE_NAME_MAX_LENGTH}
                validationStatus={errorMessages['resources.name'] ? 'error' : undefined}
              />
              {errorMessages['resources.name'] && (
                <FormControl.Validation variant="error">{errorMessages['resources.name']}</FormControl.Validation>
              )}
            </FormControl>
            <FormControl required>
              <FormControl.Label>Content</FormControl.Label>
              <Textarea
                block
                rows={7}
                name="content"
                value={text}
                placeholder="Enter content here"
                maxLength={FILE_TEXT_MAX_LENGTH}
                validationStatus={
                  errorMessages['resources.text'] || text.length > FILE_TEXT_MAX_LENGTH ? 'error' : undefined
                }
                onChange={e => {
                  setText(e.target.value)
                  setErrorMessages(prev => ({...prev, 'resources.text': ''}))
                }}
              />
              {errorMessages['resources.text'] ? (
                <FormControl.Validation variant="error">{errorMessages['resources.text']}</FormControl.Validation>
              ) : (
                <CharacterCount text={text} promptCharLimit={FILE_TEXT_MAX_LENGTH} />
              )}
            </FormControl>
          </Stack>
        </form>
      </ScopedCommands>
    </Dialog>
  )
}

function CharacterCount({text, promptCharLimit}: {text: string; promptCharLimit: number}) {
  const tooLong = text.length > promptCharLimit
  const currentCount = (
    <>
      {text.length.toLocaleString()} / {promptCharLimit.toLocaleString()} characters
    </>
  )

  if (tooLong) {
    return <FormControl.Validation variant="error">{currentCount}</FormControl.Validation>
  }

  return (
    // This is a direct child, it just doesn't know that because it is a fragment within a function call
    // eslint-disable-next-line primer-react/direct-slot-children
    <FormControl.Caption>{currentCount}</FormControl.Caption>
  )
}
