import type {CopilotSpacesConfigPayload, CustomCopilotFreeTextResource} from '@github-ui/custom-copilots/types'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {ScopedCommands} from '@github-ui/ui-commands'
import {Button, Dialog, FormControl, Stack, Textarea, TextInput} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useEffect, useState} from 'react'

import {useGetCopilotSpaceResourceSizes} from './hooks/use-get-copilot-space-resource-sizes'

interface TextFileDialogProps {
  resource?: CustomCopilotFreeTextResource
  onClose: () => void
  onSave: (resource: CustomCopilotFreeTextResource) => void
  sizePercentage?: number
}

const FILE_NAME_MAX_LENGTH = 1_000

export function TextFileDialog({sizePercentage, onClose, onSave, resource}: TextFileDialogProps) {
  const {
    copilotSpacesConfig: {maxContentSize},
  } = useAppPayload<CopilotSpacesConfigPayload>()
  const [name, setName] = useState(resource?.name || '')
  const [text, setText] = useState(resource?.text || '')
  const [isValidating, setIsValidating] = useState(false)
  const [validationError, setValidationError] = useState('')

  const [overSpaceLimit, setOverSpaceLimit] = useState(false)
  const originalContent = resource?.text ?? ''

  const [errorMessages, setErrorMessages] = useState<Record<string, string>>({})

  const {getCopilotSpaceResourceSizes} = useGetCopilotSpaceResourceSizes()

  const handleSubmit = async (e?: React.FormEvent): Promise<void> => {
    e?.preventDefault()

    const nameMissing = !name.trim()
    const textMissing = !text.trim()
    if (nameMissing || textMissing) {
      setErrorMessages(prev => ({
        ...prev,
        'resources.name': nameMissing ? 'Name is required' : '',
        'resources.text': textMissing ? 'Content is required' : '',
      }))
      return
    }

    setIsValidating(true)
    setValidationError('')

    try {
      const newResource = {
        id: resource?.id || Date.now().toString(),
        databaseId: resource?.databaseId,
        type: 'free_text',
        name,
        text,
        markedForDestroy: false,
      } as CustomCopilotFreeTextResource

      const validationResult = await getCopilotSpaceResourceSizes({
        resources: [newResource],
      })

      onSave({...newResource, sizePercentage: validationResult[newResource.id]})
      onClose()
    } catch {
      setValidationError('An unexpected error occurred while validating the text file')
    } finally {
      setIsValidating(false)
    }
  }

  return (
    <Dialog
      width="large"
      title="Add a text file"
      onClose={onClose}
      renderFooter={() => (
        <Dialog.Footer>
          <div className="d-flex flex-row flex-justify-end gap-2">
            <Button onClick={onClose}>Cancel</Button>
            <Button
              variant="primary"
              onClickCapture={overSpaceLimit ? undefined : handleSubmit}
              loadingAnnouncement="Validating resource"
              inactive={overSpaceLimit}
              loading={isValidating}
            >
              Add
            </Button>
          </div>
        </Dialog.Footer>
      )}
    >
      {validationError && <Banner variant="critical" className="mb-2" title={validationError} />}
      <ScopedCommands commands={{'github:submit-form': () => void handleSubmit()}}>
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
                onChange={e => {
                  setText(e.target.value)
                  setErrorMessages(prev => ({...prev, 'resources.text': ''}))
                }}
              />
              {errorMessages['resources.text'] ? (
                <FormControl.Validation variant="error">{errorMessages['resources.text']}</FormControl.Validation>
              ) : (
                sizePercentage !== undefined && (
                  <CharacterCount
                    text={text}
                    percentage={sizePercentage}
                    resourceContent={originalContent}
                    setOverSpaceLimit={setOverSpaceLimit}
                    maxContentSize={maxContentSize}
                  />
                )
              )}
            </FormControl>
          </Stack>
        </form>
      </ScopedCommands>
    </Dialog>
  )
}

function CharacterCount({
  text,
  percentage,
  resourceContent,
  setOverSpaceLimit,
  maxContentSize,
}: {
  text: string
  percentage: number
  resourceContent: string
  setOverSpaceLimit: React.Dispatch<React.SetStateAction<boolean>>
  maxContentSize: number
}) {
  const currentChars = (percentage / 100) * maxContentSize

  // if the user's added text is more than the resource content, the diff should be positive
  const diff =
    text.length > resourceContent.length
      ? Math.abs(text.length - resourceContent.length)
      : -Math.abs(text.length - resourceContent.length)

  const potentialChars = currentChars + diff
  // Use Math.floor to ensure the percentage does not prematurely show 100% when slightly below the threshold.
  const potentialPercentage = Math.floor((potentialChars / maxContentSize) * 100)
  const tooLong = potentialChars > maxContentSize

  useEffect(() => {
    setOverSpaceLimit(tooLong)
  }, [tooLong, setOverSpaceLimit])

  if (tooLong) {
    return (
      <FormControl.Validation variant="error">{`Total percent used: ${potentialPercentage}%`}</FormControl.Validation>
    )
  }

  return (
    // This is a direct child, it just doesn't know that because it is a fragment within a function call
    // eslint-disable-next-line primer-react/direct-slot-children
    <FormControl.Caption>{`Total percent used: ${potentialPercentage}%`}</FormControl.Caption>
  )
}
