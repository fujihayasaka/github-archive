import {KebabHorizontalIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Heading, IconButton, ProgressBar, Stack} from '@primer/react'
import {useEffect, useState} from 'react'

import styles from './GettingStarted.module.css'
import type {StepData} from './Stepper/Stepper'
import {Stepper} from './Stepper/Stepper'
import {useClickAnalytics} from '@github-ui/use-analytics'

export interface GettingStartedProps {
  stepMetadata: StepData[]
  dismissed: boolean
  onDismiss?: () => void
  checklist: boolean[]
  onChecklistChange?: (checklist: boolean[]) => void
  trackStepComplete?: (index: number) => void
  largeHeader?: boolean
  dashboardChecklist?: boolean
  dismissText?: string
}

export default function GettingStarted({
  stepMetadata,
  dismissed,
  checklist,
  onDismiss,
  onChecklistChange,
  largeHeader,
  dashboardChecklist = false,
  trackStepComplete,
  dismissText,
}: GettingStartedProps) {
  const firstIncompleteIndex = checklist.findIndex(step => !step)
  const [activeStep, setActiveStep] = useState(firstIncompleteIndex !== -1 ? firstIncompleteIndex : 0)

  const populatedSteps = stepMetadata.map((step, i) => ({
    ...step,
    isComplete: checklist[i] ?? false,
  }))
  const [steps, setSteps] = useState(populatedSteps)
  const [isDismissed, setIsDismissed] = useState(dismissed)
  const [isUpdating, setIsUpdating] = useState(false)

  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const dismissChecklist = () => {
    onDismiss?.()
    setIsDismissed(true)
  }

  const handleStepChange = (index: number) => {
    setActiveStep(index)
  }

  const handleStepComplete = (index: number) => {
    setIsUpdating(true)

    if (!steps[index]?.autoComplete) {
      setActiveStep(index + 1)
      setSteps(prev => prev.map((step, i) => (i === index ? {...step, isComplete: true} : step)))
      trackStepComplete?.(index)
    }

    if (steps[index]?.analytics) {
      sendClickAnalyticsEvent({
        category: steps[index].analytics.category,
        action: steps[index].analytics.action,
      })
    }
  }

  useEffect(() => {
    if (!isUpdating) return

    onChecklistChange?.(steps.map(step => step.isComplete))
    setIsUpdating(false)
  }, [steps, isUpdating, onChecklistChange])

  if (isDismissed) return null

  return (
    <Stack
      direction="vertical"
      gap="normal"
      className={dashboardChecklist ? 'mb-3' : 'mt-3'}
      data-testid="getting-started-checklist"
    >
      <Stack direction="horizontal" justify="space-between" align="center">
        <Heading id="checklist-heading" as="h2" className={`${styles.header} ${largeHeader ? styles.large : ''}`}>
          Getting started
        </Heading>
        <Stack direction="horizontal" gap="condensed" align="center">
          <ProgressBar
            barSize="small"
            aria-hidden="true"
            progress={(steps.filter(step => step.isComplete).length / steps.length) * 100}
            className={styles.progressBar}
          />
          <span className={styles.progressText}>
            {steps.filter(step => step.isComplete).length}/{steps.length} complete
          </span>

          <ActionMenu>
            <ActionMenu.Anchor>
              <IconButton
                icon={KebabHorizontalIcon}
                aria-label="Remove section"
                variant="invisible"
                data-testid="checklist-options"
              />
            </ActionMenu.Anchor>
            <ActionMenu.Overlay align="end">
              <ActionList>
                <ActionList.LinkItem onClick={dismissChecklist} data-testid="checklist-remove-option">
                  {dismissText || 'Remove'}
                </ActionList.LinkItem>
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </Stack>
      </Stack>
      <Stepper
        steps={steps}
        activeStepIndex={activeStep}
        onStepChange={handleStepChange}
        onStepComplete={handleStepComplete}
      />
    </Stack>
  )
}
