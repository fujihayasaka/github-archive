import {RadioGroup, FormControl, Radio, ActionList, CheckboxGroup, Checkbox} from '@primer/react'
import {Banner, Dialog} from '@primer/react/experimental'
import {LABELS} from '../../../constants/labels'
import {MESSAGES} from '../../../constants/messages'
import type {
  SubscriptionState,
  ThreadSubscriptionEvent,
} from '../../../mutations/__generated__/updateIssueSubscriptionMutation.graphql'
import {useState} from 'react'
import {useRelayEnvironment} from 'react-relay'
import {commitUpdateIssueSubscriptionMutation} from '../../../mutations/update-issue-subscription'
import {clsx} from 'clsx'
import styles from './NotificationSettingsDialog.module.css'
import {announce} from '@github-ui/aria-live'

type NotificationSettingsDialogProps = {
  title: string
  onClose: () => void
  returnFocusRef: React.RefObject<HTMLElement>
  threadId: string
  /** Custom events the user previously selected for this issue */
  preselectedViewerSubscriptionEvents: ThreadSubscriptionEvent[]
  /** Whether the user is currently subscribed to this issue */
  subscribed: boolean
}

export const NotificationSettingsDialog = ({
  onClose,
  title,
  returnFocusRef,
  preselectedViewerSubscriptionEvents,
  subscribed,
  threadId,
}: NotificationSettingsDialogProps) => {
  // Detect if the user is currently subscribed (either regularly or with custom options) or unsubscribed
  const preselectedOption = subscribed
    ? LABELS.notifications.subscribedOptionLabel
    : LABELS.notifications.unubscribedOptionLabel

  const [currentlySelectedOption, setCurrentlySelectedOption] = useState<string>(
    subscribed && preselectedViewerSubscriptionEvents.length > 0
      ? LABELS.notifications.customOptionLabel
      : preselectedOption,
  )
  const [currentlySelectedCustomOptions, setCurrentlySelectedCustomOptions] = useState<string[]>(
    preselectedViewerSubscriptionEvents,
  )
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false)
  const [error, setError] = useState<boolean>(false)
  const [showValidationError, setShowValidationError] = useState<boolean>(false)

  const environment = useRelayEnvironment()

  // Helper methods to see which high-level option to preselect when opening for the first time and whether to pre-check any of the custom options on render
  const isSelected = (option: string) => option === currentlySelectedOption
  const isCustomOptionSelected = (option: string) => currentlySelectedCustomOptions.includes(option)

  const customSecltionMissing =
    isSelected(LABELS.notifications.customOptionLabel) && currentlySelectedCustomOptions.length === 0

  const onSave = () => {
    // If the user has selected "Custom", but no sub-options, show a validation error and do not proceed with saving.
    if (customSecltionMissing) {
      setShowValidationError(true)
      return
    }
    setError(false)
    setIsSubmitting(true)
    commitUpdateIssueSubscriptionMutation({
      environment,
      input: {
        subscribableId: threadId,
        state: currentlySelectedOption as SubscriptionState,
        events: currentlySelectedCustomOptions as ThreadSubscriptionEvent[],
      },
      onCompleted: () => {
        setIsSubmitting(false)
        onClose()
      },
      onError: () => {
        setError(true)
        setIsSubmitting(false)
        announce(LABELS.notifications.errorMessage)
      },
    })
  }

  // Helper methods for rendering efficiently
  type renderOptionProps = {
    label: string
    option: string
    description: string
    last?: boolean
  }

  const renderRadioOption = ({label, option, description, last}: renderOptionProps) => (
    <div key={`${label}-${option}`}>
      <FormControl>
        <Radio
          value={title}
          name="subscriptionOption"
          checked={isSelected(option)}
          onChange={() => handleOptionChange(option)}
        />
        <FormControl.Label>{label}</FormControl.Label>
        <FormControl.Caption>{description}</FormControl.Caption>
      </FormControl>
      {!last && <ActionList.Divider />}
    </div>
  )

  const renderCheckboxOption = ({option, label, description}: renderOptionProps) => (
    <FormControl key={`${label}-${option}`}>
      <Checkbox value={option} checked={isCustomOptionSelected(option)} onChange={() => handleCheckboxChange(option)} />
      <FormControl.Label>{label}</FormControl.Label>
      <FormControl.Caption>{description}</FormControl.Caption>
    </FormControl>
  )

  const handleOptionChange = (option: string) => {
    setCurrentlySelectedOption(option)
    setCurrentlySelectedCustomOptions([])
    setShowValidationError(false)
  }

  const handleCheckboxChange = (option: string) => {
    setShowValidationError(false)
    setCurrentlySelectedCustomOptions(prevOptions =>
      prevOptions.includes(option) ? prevOptions.filter(opt => opt !== option) : [...prevOptions, option],
    )
  }

  return (
    <Dialog
      aria-label={LABELS.notifications.notificationsSettings}
      title={title}
      onClose={onClose}
      width="large"
      returnFocusRef={returnFocusRef}
      footerButtons={[
        {content: LABELS.notifications.cancel, onClick: onClose, buttonType: 'normal'},
        {
          content: isSubmitting ? LABELS.notifications.saving : LABELS.notifications.save,
          onClick: onSave,
          buttonType: 'primary',
        },
      ]}
    >
      {error && (
        <Banner variant="critical" title="Error">
          {LABELS.notifications.errorMessage}
        </Banner>
      )}
      <div className={error ? clsx(styles.radioGroup) : ''}>
        <RadioGroup name="notificationSettingsGroup">
          <RadioGroup.Label visuallyHidden>{LABELS.notifications.notificationsSettings}</RadioGroup.Label>
          {[
            {
              label: LABELS.notifications.notSubscribedOption,
              description: MESSAGES.notSubscribedDescription,
              option: LABELS.notifications.unubscribedOptionLabel,
            },
            {
              label: LABELS.notifications.subscribedOption,
              description: MESSAGES.subscribedDescription,
              option: LABELS.notifications.subscribedOptionLabel,
            },
            {
              label: LABELS.notifications.customOption,
              description: MESSAGES.customDescription,
              option: LABELS.notifications.customOptionLabel,
              last: true,
            },
          ].map(renderRadioOption)}

          {currentlySelectedOption === LABELS.notifications.customOptionLabel && (
            <div className={clsx(styles.checkboxGroup)}>
              <CheckboxGroup>
                <CheckboxGroup.Label visuallyHidden>{LABELS.notifications.customOptions}</CheckboxGroup.Label>
                {[
                  {
                    option: LABELS.notifications.closedLabel,
                    label: LABELS.notifications.closed,
                    description: MESSAGES.subscribedToClosedDescription,
                  },
                  {
                    option: LABELS.notifications.reopenedLabel,
                    label: LABELS.notifications.reopened,
                    description: MESSAGES.subscribedToReopenedDescription,
                  },
                ].map(renderCheckboxOption)}
              </CheckboxGroup>
            </div>
          )}
          {showValidationError && (
            <RadioGroup.Validation variant="error">{MESSAGES.customSelectionMissing}</RadioGroup.Validation>
          )}
        </RadioGroup>
      </div>
    </Dialog>
  )
}
