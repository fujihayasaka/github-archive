/* eslint eslint-comments/no-use: off */
import {FormControl, Portal, Textarea, TextInput} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import type React from 'react'
import {useState} from 'react'

import {dashboardLocalStorage} from '../utils/dashboard-local-storage'

import styles from '../DashboardLists.module.css'

export interface PromptDialogProps {
  promptDialogRef: React.MutableRefObject<HTMLDivElement | null>
  initialPrompt: string
  initialTemperature: number
  onDismiss: () => void
}

export const PromptDialog = ({
  onDismiss,
  promptDialogRef,
  initialPrompt,
  initialTemperature,
}: PromptDialogProps): JSX.Element => {
  const [prompt, setPrompt] = useState<string>(initialPrompt)
  const [temperature, setTemperature] = useState(initialTemperature)
  const savePrompt = () => {
    dashboardLocalStorage.setIssueSummaryPrompt(prompt)
    dashboardLocalStorage.setIssueSummaryTemperature(temperature)
    onDismiss()
  }

  return (
    <Portal>
      <Dialog
        ref={promptDialogRef}
        onClose={onDismiss}
        title={'Issue Summary Prompt Settings'}
        width="xlarge"
        className={styles.Dialog}
      >
        <Dialog.Body>
          <FormControl>
            <FormControl.Label>System Instructions</FormControl.Label>
            <FormControl.Caption>
              <span>Make adjustments to the system instructions or add new instructions.</span>
            </FormControl.Caption>
            <Textarea
              block
              className={styles.TextArea}
              aria-label="Prompt"
              name="Prompt"
              value={prompt}
              onChange={e => setPrompt(e.target.value)}
            />
          </FormControl>
          <FormControl className={styles.FormControl}>
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
