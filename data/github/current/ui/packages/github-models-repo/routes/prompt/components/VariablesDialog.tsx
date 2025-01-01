import {CommandButton, ScopedCommands} from '@github-ui/ui-commands'
import {Button, Dialog, FormControl, Textarea} from '@primer/react'
import {useState} from 'react'
import type {RepoModel} from '../../../types'
import {NoVariablesMessage} from './NoVariablesMessage'
import styles from './VariablesDialog.module.css'
export interface VariablesDialogProps {
  primaryTitle: string
  variables: Record<string, string>
  availableVariables: Set<string>

  /** If set, mark variable inputs as required */
  requireValues?: boolean

  onClose: (content?: Record<string, string>) => void
  model?: RepoModel | undefined
}

export function VariablesDialog({
  primaryTitle,
  variables,
  availableVariables,
  onClose,
  requireValues,
  model,
}: VariablesDialogProps) {
  const [variableContent, setVariableContent] = useState<Record<string, string>>(() => variables)
  const variableKeys = Array.from(availableVariables.keys())
  const anyVariables = variableKeys.length > 0

  const validate = () => {
    if (!anyVariables) return false
    if (!requireValues) return true

    // Are there any variables without values?
    const missingVariables = Array.from(availableVariables).filter(v => !variableContent[v])
    return missingVariables.length === 0
  }

  const footer = () => {
    return (
      <Dialog.Footer>
        <Button onClick={() => onClose()}>Cancel</Button>
        <CommandButton
          variant={anyVariables ? 'primary' : 'default'}
          commandId="github:submit-form"
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
        <p className="fgColor-muted text-small">
          To add variables, insert your variable name to the <b>Prompt</b> or <b>User</b> fields with double curly
          braces, like <code>{'{{variable_name}}'}</code>.
        </p>
        {variableKeys.map((v, i) => (
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
        {!anyVariables && <NoVariablesMessage model={model} />}
      </Dialog>
    </ScopedCommands>
  )
}
