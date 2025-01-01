import {Button, Dialog, FormControl, Textarea} from '@primer/react'
import {useState} from 'react'
import styles from './VariablesDialog.module.css'
import {CommandButton, ScopedCommands} from '@github-ui/ui-commands'

export interface VariablesDialogProps {
  primaryTitle: string
  variables: Record<string, string>
  availableVariables: string[]
  /** Optional list of required variables. If set, the primary action will be disabled unless those have a value */
  requiredVariables?: Set<string>
  onClose: (content?: Record<string, string>) => void
}

export function VariablesDialog({
  primaryTitle,
  variables,
  availableVariables,
  requiredVariables,
  onClose,
}: VariablesDialogProps) {
  const [variableContent, setVariableContent] = useState<Record<string, string>>(() => variables)

  const validate = () => {
    // Are there any required variables?
    if (requiredVariables) {
      const missingVariables = Array.from(requiredVariables).filter(v => !variableContent[v])
      return missingVariables.length === 0
    }

    return true
  }

  const footer = () => {
    return (
      <Dialog.Footer>
        <Button onClick={() => onClose()}>Cancel</Button>
        <CommandButton
          variant="primary"
          commandId="github:submit-form"
          onClick={handleSubmit}
          disabled={!validate()}
          showKeybindingHint
        >
          {primaryTitle}
        </CommandButton>
      </Dialog.Footer>
    )
  }

  const handleSubmit = () => onClose(variableContent)

  return (
    <ScopedCommands commands={{'github:submit-form': handleSubmit}}>
      <Dialog
        className={styles.variablesDialog}
        title="Variables"
        position="right"
        onClose={() => onClose()}
        renderFooter={footer}
      >
        {availableVariables.map((v, i) => (
          <FormControl key={v} className={i > 0 ? 'mt-2' : ''} required={requiredVariables?.has(v)}>
            <FormControl.Label>
              <code>{`{{${v}}}`}</code>
            </FormControl.Label>
            <Textarea
              resize="vertical"
              block
              value={variableContent[v]}
              onChange={evt =>
                setVariableContent({
                  ...variableContent,
                  [v]: evt.currentTarget.value,
                })
              }
            />
          </FormControl>
        ))}
      </Dialog>
    </ScopedCommands>
  )
}
