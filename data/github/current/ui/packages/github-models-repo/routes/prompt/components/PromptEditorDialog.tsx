import type {Model} from '@github-ui/marketplace-common'
import {Button, Dialog, FormControl, Stack} from '@primer/react'
import {useState} from 'react'
import {useModels} from '../contexts/ModelsContext'
import {findModel} from '../models'
import type {PromptConfig} from '../prompts'
import ModelPicker from './ModelPicker'
import ParameterSettingsMenu from './ParameterSettingsMenu'
import {PromptMessageEditor} from './PromptMessageEditor'
import styles from './VariablesDialog.module.css'

export interface PromptEditorDialogProps {
  title?: string
  primaryLabel?: string
  prompt?: PromptConfig
  onSave: (prompt: PromptConfig) => void
  onClose: () => void
}

export function PromptEditorDialog({title, primaryLabel, prompt, onSave, onClose}: PromptEditorDialogProps) {
  const [editablePrompt, setEditablePrompt] = useState<PromptConfig>(
    prompt ||
      ({
        messages: [
          {
            timestamp: new Date(),
            role: 'system',
            message: '',
          },
          {
            timestamp: new Date(),
            role: 'user',
            message: '',
          },
        ],
      } as PromptConfig),
  )

  const handleSelectModel = (model: Model) => {
    setEditablePrompt(prev => {
      return {
        ...prev,
        model: model.id,
      }
    })
  }

  const models = useModels()
  const model = editablePrompt?.model ? findModel(editablePrompt.model, models) : undefined

  return (
    <Dialog
      className={styles.variablesDialog}
      title={title || 'Edit prompt'}
      position="right"
      onClose={() => onClose()}
    >
      <Stack>
        <FormControl>
          <FormControl.Label>Model</FormControl.Label>
          <div className="d-flex flex-row">
            <ModelPicker selectedModel={model} onSelect={handleSelectModel} />
            <ParameterSettingsMenu
              iconSize="medium"
              className="ml-2"
              model={model}
              modelParameters={editablePrompt.modelParameters ?? {}}
              handleModelParamsChange={({key, value}) => {
                // TODO: Validate parameters if validate is set

                setEditablePrompt(prev => {
                  return {
                    ...prev,
                    modelParameters: {
                      ...prev.modelParameters,
                      [key]: value,
                    },
                  }
                })
              }}
            />
          </div>
        </FormControl>

        <PromptMessageEditor
          messages={editablePrompt.messages ?? []}
          updateMessages={messages => {
            setEditablePrompt(prev => {
              return {
                ...prev,
                messages,
              }
            })
          }}
        />
      </Stack>

      <Dialog.Footer>
        <Button onClick={() => onClose()}>Cancel</Button>
        <Button
          variant="primary"
          onClick={() => onSave(editablePrompt)} // Pass prompt to onSave
          // disabled={!validate()} // Disable if validation fails
        >
          {primaryLabel || 'Update'}
        </Button>
      </Dialog.Footer>
    </Dialog>
  )
}
