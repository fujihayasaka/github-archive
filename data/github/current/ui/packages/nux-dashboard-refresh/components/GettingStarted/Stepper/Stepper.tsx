import {CheckCircleFillIcon, CircleIcon} from '@primer/octicons-react'
import {Heading, LinkButton} from '@primer/react'
import type React from 'react'
import {useState} from 'react'

import styles from './Stepper.module.css'

export type StepData = {
  title: string
  description?: string | React.ReactNode | ((props: {onComplete: () => void}) => React.ReactNode)
  ctaLabel?: string
  href?: string
  customContent?: React.ReactNode
  customCta?: (props: {onComplete: () => void; index: number; isActive: boolean}) => React.ReactNode
  completed?: boolean
  isComplete?: boolean
  autoComplete?: boolean
  analytics?: {
    category: string
    action: string
  }
}

export type StepperProps = {
  steps: StepData[]
  activeStepIndex?: number
  onStepChange?: (newIndex: number) => void
  onStepComplete?: (index: number) => void
  initialStep?: number
}

export const Stepper: React.FC<StepperProps> = ({
  steps,
  activeStepIndex,
  onStepChange,
  onStepComplete,
  initialStep = 0,
}) => {
  const isControlled = activeStepIndex !== undefined
  const [internalActiveIndex, setInternalActiveIndex] = useState<number>(initialStep)
  const currentActive = isControlled ? activeStepIndex : internalActiveIndex

  const handleStepClick = (index: number) => {
    if (index === currentActive) return
    if (isControlled) {
      onStepChange?.(index)
    } else {
      setInternalActiveIndex(index)
    }
  }

  return (
    <ol className={styles.stepper}>
      {steps.map((step, index) => {
        const isActive = index === currentActive
        const stepId = `step-${index}`
        const panelId = `panel-${index}`

        const renderDescription = () => {
          if (!step.description) return null
          let content: React.ReactNode
          if (typeof step.description === 'function') {
            content = step.description({
              onComplete: () => {
                if (step.isComplete || !onStepComplete) return
                onStepComplete(index)
              },
            })
          } else {
            content = step.description
          }
          return <div className={styles.description}>{content}</div>
        }

        const renderCustomCta = () =>
          step.customCta &&
          step.customCta({
            onComplete: () => {
              if (step.isComplete || !onStepComplete) return
              onStepComplete(index)
            },
            index,
            isActive,
          })

        const renderCtaButton = () =>
          step.ctaLabel && (
            <LinkButton
              href={step.href}
              variant="primary"
              className={styles.cta}
              tabIndex={isActive ? 0 : -1}
              onClick={e => {
                if (step.isComplete || !onStepComplete) return
                e.preventDefault()
                onStepComplete(index)
                if (step.href) {
                  window.location.href = step.href
                }
              }}
              data-testid={`stepper-cta-${index}`}
            >
              {step.ctaLabel}
            </LinkButton>
          )

        return (
          <li
            key={stepId}
            className={`${styles.step} ${isActive ? styles.active : ''}`} // ${step.isComplete ? styles.completed : ''} style is missing
          >
            <button
              className={styles.header}
              onClick={() => handleStepClick(index)}
              aria-expanded={isActive}
              aria-controls={panelId}
              id={stepId}
              data-testid={`stepper-button-${index}`}
            >
              <span className={styles.stepIndex} aria-hidden="true">
                {step.isComplete ? (
                  <CheckCircleFillIcon
                    className={styles.checkIcon}
                    size={16}
                    data-testid={`stepper-${stepId}-checked`}
                  />
                ) : (
                  <CircleIcon className={styles.circleIcon} size={16} data-testid={`stepper-${stepId}-unchecked`} />
                )}
              </span>
              <Heading as="h3" className={styles.stepTitle}>
                {step.title}
              </Heading>
            </button>

            <div
              id={panelId}
              role="region"
              aria-labelledby={stepId}
              aria-hidden={!isActive}
              className={`${styles.panel} ${isActive ? styles.open : ''}`}
              data-testid={`stepper-panel-${index}`}
            >
              {step.customContent ? (
                step.customContent
              ) : (
                <>
                  {renderDescription()}
                  {renderCustomCta() || renderCtaButton()}
                </>
              )}
            </div>
          </li>
        )
      })}
    </ol>
  )
}
