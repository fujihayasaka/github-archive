import {useState, useMemo} from 'react'
import {Button, Dialog, FormControl, Stack} from '@primer/react'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useModels} from '../contexts/ModelsContext'
import {findModel} from '../models'
import type {PromptConfig} from '../prompts'
import {referencedVariablesInPrompt} from '../variables'
import {extractMessagePairs, updateMessagePairs} from '../utils/message-utils'
import ModelPicker from './ModelPicker'
import ParameterSettings, {ParameterSettingsButton, useParameterSettings} from './ParameterSettings'
import {PromptMessageEditor} from './PromptMessageEditor'
import {PromptMessagePair} from './PromptMessagePair'
import styles from './VariablesDialog.module.css'

export interface PromptEditorDialogProps {
  title?: string
  primaryLabel?: string
  prompt?: PromptConfig
  onSave: (prompt: PromptConfig) => void
  onClose: () => void
}

export function PromptEditorDialog({prompt, title, primaryLabel, onSave, onClose}: PromptEditorDialogProps) {
  const now = new Date()
  const [editablePrompt, setEditablePrompt] = useState<PromptConfig>(
    prompt ||
      ({
        messages: [
          {timestamp: now, role: 'system', message: ''},
          {timestamp: now, role: 'user', message: ''},
        ],
      } as PromptConfig),
  )
  const models = useModels()

  const model = useMemo(() => {
    return editablePrompt?.model ? findModel(editablePrompt.model, models) : undefined
  }, [editablePrompt, models])
  const parameterSettingsProps = useParameterSettings(editablePrompt)

  const messagePairFlagEnabled = useFeatureFlag('github_models_prompt_message_pair')

  // Extract referenced variables for autocomplete
  const referencedVariables = useMemo(
    () => new Set<string>(referencedVariablesInPrompt(editablePrompt)),
    [editablePrompt],
  )

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
          <Stack gap="condensed" justify="space-between" direction="horizontal" className="width-full">
            <ModelPicker
              selectedModel={model}
              onSelect={m => setEditablePrompt({...editablePrompt, model: m.original_name})}
            />
            <ParameterSettingsButton {...parameterSettingsProps} />
          </Stack>
        </FormControl>

        <ParameterSettings
          {...parameterSettingsProps}
          setParameters={modelParameters => setEditablePrompt({...editablePrompt, modelParameters})}
          setResponseFormat={responseFormat => setEditablePrompt({...editablePrompt, responseFormat})}
          setJsonSchema={jsonSchema => setEditablePrompt({...editablePrompt, jsonSchema})}
        />

        <PromptMessageEditor
          selectedModel={model}
          messages={editablePrompt.messages ?? []}
          updateMessages={messages => setEditablePrompt({...editablePrompt, messages})}
        />

        {messagePairFlagEnabled && (
          <div className="mt-3">
            <PromptMessagePair
              messagePairs={extractMessagePairs(editablePrompt.messages || [])}
              setMessagePairs={pairs => {
                const updatedMessages = updateMessagePairs(editablePrompt.messages || [], pairs)
                setEditablePrompt({
                  ...editablePrompt,
                  messages: updatedMessages,
                })
              }}
              variableKeys={Array.from(referencedVariables)}
            />
          </div>
        )}
      </Stack>

      <Dialog.Footer className={styles.footer}>
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
