/* eslint eslint-comments/no-use: off */
import {PlusIcon, TrashIcon} from '@primer/octicons-react'
import {Box, Button, FormControl, IconButton, Portal, Stack, Textarea, TextInput, ToggleSwitch} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import React, {useState} from 'react'

import type {Tool} from '../utils/copilot-chat-types'
import {copilotLocalStorage} from '../utils/copilot-local-storage'
import {useChatManager} from '../utils/CopilotChatManagerContext'

export interface PromptDialogProps {
  promptDialogRef: React.MutableRefObject<HTMLDivElement | null>
  onDismiss: () => void
}

export const PromptDialog = ({onDismiss, promptDialogRef}: PromptDialogProps): JSX.Element => {
  const initialState = copilotLocalStorage.settings
  const [systemInstructions, setSystemInstructions] = useState(initialState?.instructionPrompt || '')
  const [tools, setTools] = useState<Tool[]>(initialState?.skillOverrides ?? [])
  const [temperature, setTemperature] = useState(initialState?.temperature || 0.7)
  const manager = useChatManager()
  const savePrompt = () => {
    const toolsArray = tools.filter(tool => tool.slug && tool.description)
    manager.setCopilotSettings({instructionPrompt: systemInstructions, skillOverrides: toolsArray, temperature})
    onDismiss()
  }

  return (
    <Portal>
      <Dialog
        ref={promptDialogRef}
        onClose={onDismiss}
        title={'Prompt Settings'}
        width="xlarge"
        sx={{overflow: 'auto'}}
      >
        <Dialog.Body>
          <Box sx={{p: 3}}>
            <FormControl>
              <FormControl.Label>System Instructions</FormControl.Label>
              <FormControl.Caption>
                <span>Make adjustments to the system instructions or add new instructions.</span>
              </FormControl.Caption>
              <Textarea
                block
                sx={{my: 2}}
                aria-label="Prompt"
                name="Prompt"
                value={systemInstructions}
                onChange={e => setSystemInstructions(e.target.value)}
              />
            </FormControl>
            <FormControl sx={{pt: 3}}>
              <FormControl.Label>Temperature</FormControl.Label>
              <FormControl.Caption>
                Controls the randomness of the model&apos;s responses. Lower temperatures are more deterministic, while
                higher temperatures are more random.
              </FormControl.Caption>
              <TextInput
                type="number"
                min="0"
                max="1"
                step="0.01"
                block
                value={temperature}
                onChange={e => setTemperature(Number(e.target.value))}
              />
            </FormControl>
            <Box sx={{fontSize: 3, py: 3}}>Tools</Box>
            {tools.map((tool, key) => (
              <React.Fragment key={`tool-${tool.slug}-${Math.random()}`}>
                <Stack direction="horizontal" sx={{py: 2}}>
                  <FormControl>
                    <FormControl.Label>Name</FormControl.Label>
                    <FormControl.Caption>
                      <span>Slug of tool you want to adjust</span>
                    </FormControl.Caption>
                    <TextInput
                      defaultValue={tool.slug}
                      onChange={e => {
                        tools.map((t, index) => {
                          if (index === key) {
                            t.slug = e.target.value
                          }
                        })
                      }}
                    />
                  </FormControl>
                  <FormControl>
                    <FormControl.Label>Description</FormControl.Label>
                    <FormControl.Caption>
                      <span>Make changes to the tool description</span>
                    </FormControl.Caption>
                    <TextInput
                      defaultValue={tool.description}
                      onChange={e => {
                        tools.map((t, index) => {
                          if (index === key) {
                            tool.description = e.target.value
                          }
                        })
                      }}
                    />
                  </FormControl>
                  <FormControl>
                    <FormControl.Label id="toggle">Enabled?</FormControl.Label>
                    <ToggleSwitch
                      size="small"
                      aria-labelledby="toggle"
                      defaultChecked={tool.enabled}
                      onChange={newValue => {
                        tools.map((t, index) => {
                          if (index === key) {
                            t.enabled = newValue
                          }
                        })
                      }}
                    />
                  </FormControl>
                  <IconButton
                    icon={TrashIcon}
                    aria-label="Delete tool"
                    variant="invisible"
                    sx={{mt: '20px'}}
                    onClick={() => {
                      const newTools = [...tools]
                      if (tools.length === 1) {
                        setTools([])
                      } else {
                        newTools.splice(key, 1)
                        setTools(newTools)
                      }
                    }}
                  />
                </Stack>
                {key === tools.length - 1 && (
                  <Button
                    leadingVisual={<PlusIcon />}
                    onClick={() => setTools([...tools, {slug: '', description: '', enabled: true}])}
                    variant="invisible"
                    size="small"
                  >
                    Add another tool
                  </Button>
                )}
              </React.Fragment>
            ))}
            {tools.length === 0 && (
              <Button
                leadingVisual={<PlusIcon />}
                onClick={() => setTools([...tools, {slug: '', description: '', enabled: true}])}
                variant="invisible"
                size="small"
              >
                Add a tool
              </Button>
            )}
          </Box>
        </Dialog.Body>
        <Dialog.Footer>
          <Dialog.Buttons
            buttons={[
              {type: 'button', onClick: onDismiss, content: 'Cancel'},
              {type: 'submit', onClick: savePrompt, content: 'Save', buttonType: 'primary'},
            ]}
          />
        </Dialog.Footer>
      </Dialog>
    </Portal>
  )
}
