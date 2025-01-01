import {Dialog, FormControl, Stack, TextInput, type DialogButtonProps} from '@primer/react'
import cloneDeep from 'lodash-es/cloneDeep'
import React, {useState} from 'react'
import type {EvaluatorCfg} from '../../evals-sdk/config'
import type {EvaluatorTemplate} from '../../evaluator-template'
import {usePromptEvalsManager} from '../../prompt-evals-manager'
import {LLMEvaluatorContent, validateLLMEvaluator} from './LLMEvaluatorContent'
import {StringCheckContent, validateStringCheck} from './StringCheckContent'

function validate(config: EvaluatorCfg): string | null {
  if (!config.name) {
    return 'Name is required'
  }

  if (config.string) {
    return validateStringCheck(config.string)
  }

  if (config.llm) {
    return validateLLMEvaluator(config.llm)
  }

  return null
}

export type EvaluatorDialogProps = {
  template?: EvaluatorTemplate

  evaluatorIndex?: number
  evaluator?: EvaluatorCfg

  onClose: () => void
}

type Mode = 'add' | 'edit'

export function EvaluatorDialog({template, evaluatorIndex, evaluator, onClose}: EvaluatorDialogProps) {
  const manager = usePromptEvalsManager()

  const mode: Mode = evaluator ? 'edit' : 'add'
  const readonly = (mode === 'add' && template!.readonly) || false

  const [config, setConfig] = React.useState<EvaluatorCfg>(() => {
    if (template) {
      // We don't want to modify the config template itself, so do a deep clone
      return cloneDeep(template.configTemplate)
    }

    return evaluator!
  })

  // Start with an empty validation status, we'll check when submitting
  const [validationStatus, setValidationStatus] = useState<string | null>(null)

  const innerContent = getContent(config, readonly, setConfig)

  const handlePrimary = () => {
    const valid = validate(config)
    if (valid) {
      setValidationStatus(valid)
      return
    }

    switch (mode) {
      case 'add': {
        manager.evalsAddEvaluator({
          config,
        })
        break
      }

      case 'edit': {
        manager.evalsUpdateEvaluator(evaluatorIndex!, config)
        break
      }
    }

    onClose()
  }

  const buttons: DialogButtonProps[] = [
    {
      content: 'Cancel',
      onClick: onClose,
    },
  ]

  if (mode !== 'edit' || !readonly) {
    buttons.push({
      buttonType: 'primary',
      content: mode === 'add' ? 'Add' : 'Update',
      onClick: handlePrimary,
    })
  }

  return (
    <Dialog
      title={mode === 'add' ? 'Add test criteria' : 'Edit test criteria'}
      onClose={onClose}
      footerButtons={buttons}
    >
      <Stack>
        <FormControl required>
          <FormControl.Label>Name</FormControl.Label>
          <TextInput
            disabled={readonly}
            value={config.name}
            onInput={evt => {
              setConfig({
                ...config,
                name: evt.currentTarget.value,
              })
            }}
          />
        </FormControl>
        {innerContent}
        {validationStatus && <FormControl.Validation variant="error">{validationStatus}</FormControl.Validation>}
      </Stack>
    </Dialog>
  )
}
function getContent(
  config: EvaluatorCfg,
  readonly: boolean,
  setConfig: React.Dispatch<React.SetStateAction<EvaluatorCfg>>,
) {
  if (config.string) {
    return (
      <StringCheckContent
        e={config.string}
        readonly={readonly}
        updateEvaluator={e => {
          setConfig({
            ...config,
            string: e,
          })
        }}
      />
    )
  }

  if (config.llm) {
    return (
      <LLMEvaluatorContent
        e={config.llm}
        readonly={readonly}
        updateEvaluator={e => {
          setConfig({
            ...config,
            llm: e,
          })
        }}
      />
    )
  }

  return null
}
