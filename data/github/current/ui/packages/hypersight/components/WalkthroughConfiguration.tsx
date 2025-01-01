import {NoteIcon, GearIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, Dialog, FormControl, Textarea} from '@primer/react'
import {useState, useRef, type ChangeEvent} from 'react'
import type {ExplanationDepth} from '../utils/types'
import styles from './WalkthroughConfiguration.module.css'

interface WalkthroughConfigurationProps {
  depth: ExplanationDepth
  onDepthChange: (depth: ExplanationDepth) => void
  preferences: string
  onPreferencesChange: (preferences: string) => void
}

const explanationDepths: ExplanationDepth[] = ['None', 'Light', 'Balanced', 'Moderate', 'Full']
const MAX_CHARACTERS = 600

export default function WalkthroughConfiguration({
  depth,
  onDepthChange,
  preferences,
  onPreferencesChange,
}: WalkthroughConfigurationProps) {
  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const [localPreferences, setLocalPreferences] = useState(preferences)
  const preferencesButtonRef = useRef<HTMLButtonElement>(null)

  const handleSave = () => {
    onPreferencesChange(localPreferences)
    setIsDialogOpen(false)
  }

  const handleCancel = () => {
    setLocalPreferences(preferences)
    setIsDialogOpen(false)
  }

  const handlePreferencesChange = (e: ChangeEvent<HTMLTextAreaElement>) => {
    const value = e.target.value
    if (value.length <= MAX_CHARACTERS) {
      setLocalPreferences(value)
    }
  }

  return (
    <div className={styles.container}>
      <ActionMenu>
        <ActionMenu.Button leadingVisual={NoteIcon}>Explanation: {depth}</ActionMenu.Button>
        <ActionMenu.Overlay>
          <ActionList selectionVariant="single">
            {explanationDepths.map(depthOption => (
              <ActionList.Item
                key={depthOption}
                selected={depthOption === depth}
                onSelect={() => onDepthChange(depthOption)}
              >
                {depthOption}
              </ActionList.Item>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>

      <IconButton
        ref={preferencesButtonRef}
        icon={GearIcon}
        aria-label="Configure preferences"
        onClick={() => setIsDialogOpen(true)}
      />

      {isDialogOpen && (
        <Dialog
          onClose={handleCancel}
          title="Walkthrough instructions"
          subtitle="Personalize your walkthrough with specific instructions"
          returnFocusRef={preferencesButtonRef}
          aria-labelledby="preferences-dialog-title"
          footerButtons={[
            {
              content: 'Cancel',
              onClick: handleCancel,
            },
            {
              content: 'Save',
              onClick: handleSave,
              buttonType: 'primary',
            },
          ]}
        >
          <FormControl>
            <FormControl.Label visuallyHidden>Instructions</FormControl.Label>
            <Textarea
              value={localPreferences}
              onChange={handlePreferencesChange}
              rows={6}
              block
              className={styles.textarea}
              placeholder="Your instructions..."
            />
            <FormControl.Caption>
              {localPreferences.length}/{MAX_CHARACTERS} characters
            </FormControl.Caption>
          </FormControl>
        </Dialog>
      )}
    </div>
  )
}
