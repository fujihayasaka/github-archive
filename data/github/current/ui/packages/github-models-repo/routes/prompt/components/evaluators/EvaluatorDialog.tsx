import {Dialog, FormControl, Stack, TextInput, type DialogButtonProps} from '@primer/react'
import cloneDeep from 'lodash-es/cloneDeep'
import {useState} from 'react'
import type {EvaluatorCfg} from '../../evals-sdk/config'
import type {EvaluatorTemplate} from '../../evaluator-template'
import {usePromptCompareManager} from '../../prompt-compare-manager'
import {validate} from './utils'
import {EvaluatorDialogContent} from './EvaluatorDialogContent'

export type EvaluatorDialogProps = {
  template?: EvaluatorTemplate

  evaluatorIndex?: number
  evaluator?: EvaluatorCfg

  onClose: () => void
}

type Mode = 'add' | 'edit'

export function EvaluatorDialog({template, evaluatorIndex, evaluator, onClose}: EvaluatorDialogProps) {
  const manager = usePromptCompareManager()

  const mode: Mode = evaluator ? 'edit' : 'add'
  const readonly = (mode === 'add' && template?.readonly) || false

  const [config, setConfig] = useState<EvaluatorCfg>(() => {
    if (template) {
      // We don't want to modify the config template itself, so do a deep clone
      return cloneDeep(template.configTemplate)
    }

    return evaluator!
  })

  // Start with an empty validation status, we'll check when submitting
  const [validationStatus, setValidationStatus] = useState<string | null>(null)

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
        <EvaluatorDialogContent config={config} readonly={readonly} setConfig={setConfig} />
        {validationStatus && <FormControl.Validation variant="error">{validationStatus}</FormControl.Validation>}
      </Stack>
    </Dialog>
  )
}
