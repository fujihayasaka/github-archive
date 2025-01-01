import {Button, Dialog, FormControl, Textarea} from '@primer/react'
import {useState} from 'react'
import styles from './VariablesDialog.module.css'
import {CommandButton, ScopedCommands} from '@github-ui/ui-commands'

export interface VariablesDialogProps {
  primaryTitle: string
  variables: Record<string, string>
  availableVariables: Set<string>

  /** If set, mark variable inputs as required */
  requireValues?: boolean

  onClose: (content?: Record<string, string>) => void
}

export function VariablesDialog({
  primaryTitle,
  variables,
  availableVariables,
  onClose,
  requireValues,
}: VariablesDialogProps) {
  const [variableContent, setVariableContent] = useState<Record<string, string>>(() => variables)

  const validate = () => {
    if (!requireValues) {
      return true
    }

    // Are there any variables without values?
    const missingVariables = Array.from(availableVariables).filter(v => !variableContent[v])
    return missingVariables.length === 0
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
        {Array.from(availableVariables.keys()).map((v, i) => (
          <FormControl key={v} className={i > 0 ? 'mt-2' : ''} required={requireValues}>
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
