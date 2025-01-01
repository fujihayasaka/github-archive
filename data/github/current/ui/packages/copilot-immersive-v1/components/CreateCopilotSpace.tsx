import type {CustomCopilot as CustomCopilotItem} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {ScopedCommands} from '@github-ui/ui-commands'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {Button, FormControl, Stack, Textarea} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import type React from 'react'
import {useCallback, useState} from 'react'

interface CreateCopilotSpaceProps {
  onDismiss: () => void
  createSpace?: (space: CustomCopilotItem) => void
}

export function CreateCopilotSpace({onDismiss, createSpace}: CreateCopilotSpaceProps) {
  const [isSaving, setIsSaving] = useState<boolean>(false)
  const [name, setName] = useState<string>('')
  const [description, setDescription] = useState<string>('')
  const [errorMessage, setErrorMessage] = useState<string | undefined>(undefined)

  const onSubmit = (e: React.FormEvent<HTMLElement>) => {
    void saveNewSpace(e)
  }

  const saveNewSpace = useCallback(
    async (e: React.FormEvent<HTMLElement>) => {
      e.preventDefault()

      if (isSaving) return
      setIsSaving(true)

      try {
        // TODO: add icon type and color to body (waiting on data change for custom_copilot)
        // https://github.com/github/copilot-productivity/issues/4447
        const resp = await verifiedFetchJSON('/custom_copilots', {
          method: 'POST',
          body: {
            // eslint-disable-next-line camelcase
            custom_copilot: {
              name,
              description,
            },
          },
        })

        if (resp.ok) {
          const spaceData: CustomCopilotItem = await resp.json()
          createSpace?.(spaceData)
          onDismiss()
        } else {
          const errorData = await resp.json()
          setErrorMessage(String(errorData.errorMessages.name))
        }
      } catch {
        setErrorMessage('An error occurred while creating your space')
      } finally {
        setIsSaving(false)
      }
    },
    [isSaving, name, description, createSpace, onDismiss],
  )

  return (
    <Dialog
      onClose={onDismiss}
      title="Create a new Space"
      width="large"
      renderBody={() => (
        <Dialog.Body>
          <form onSubmit={saveNewSpace}>
            <Stack>
              <FormControl>
                <FormControl.Label>Name</FormControl.Label>
                <ScopedCommands commands={{'github:submit-form': () => saveNewSpace}}>
                  <Textarea
                    block
                    rows={1}
                    name="space name"
                    aria-label="Space name"
                    resize="none"
                    value={name}
                    placeholder="Enter name"
                    onChange={e => {
                      setName(e.target.value)
                      setErrorMessage(undefined)
                    }}
                  />
                </ScopedCommands>
              </FormControl>
              <FormControl>
                <FormControl.Label>Description</FormControl.Label>
                <div className="width-full position-relative">
                  <ScopedCommands commands={{'github:submit-form': () => onSubmit}}>
                    <Textarea
                      className="width-full"
                      rows={3}
                      name="description"
                      aria-label="Description"
                      value={description}
                      placeholder="Define preferences, behaviors and output formats"
                      onChange={e => {
                        setDescription(e.target.value)
                        setErrorMessage(undefined)
                      }}
                    />
                  </ScopedCommands>
                </div>
                {errorMessage && (
                  <FormControl.Validation variant="error">
                    <span>{errorMessage}</span>
                  </FormControl.Validation>
                )}
              </FormControl>
            </Stack>
          </form>
        </Dialog.Body>
      )}
      renderFooter={() => (
        <div className="d-flex flex-row flex-justify-end pl-3 pb-3 pr-3 gap-2">
          <Button variant="default" onClick={onDismiss}>
            Cancel
          </Button>
          <Button loading={isSaving} loadingAnnouncement="Saving new space" variant="primary" onClick={saveNewSpace}>
            Create
          </Button>
        </div>
      )}
    />
  )
}
