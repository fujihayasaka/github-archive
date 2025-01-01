import {useState} from 'react'
import GettingStarted from '../GettingStarted/GettingStarted'
import type {StepData} from '../GettingStarted/Stepper/Stepper'
import {updateSetting} from '../../helpers/settings-helper'
import {DashboardDismissalSettings, GettingStartedChecklistSettings} from '../../constants/dashboard-settings'
import {LinkButton} from '@primer/react'
import styles from '../GettingStarted/Stepper/Stepper.module.css'
import {ChecklistComplete} from './ChecklistComplete/ChecklistComplete'
import {useClickAnalytics} from '@github-ui/use-analytics'

interface NewUserGettingStartedChecklistProps {
  checklist: GettingStartedChecklist
  dismissed: boolean
}

export interface GettingStartedChecklist {
  has_customized_account: boolean
  has_tried_copilot: boolean
  has_created_repo: boolean
}

const gettingStartedSteps: StepData[] = [
  {
    title: 'Complete your profile',
    description:
      'Add your personal bio and avatar — express yourself by building your social coding presence on GitHub.',
    ctaLabel: 'Update profile',
    href: '/settings/profile',
    autoComplete: true,
    analytics: {
      category: 'zero_user_dashboard',
      action: 'click.getting_started.complete_profile',
    },
  },
  {
    title: 'Chat with Copilot',
    description: 'Ask Copilot questions about coding with GitHub or start writing code for your first project.',
    customCta: ({onComplete, index, isActive}) => (
      <LinkButton
        href="/copilot"
        variant="primary"
        className={styles.cta}
        tabIndex={isActive ? 0 : -1}
        onClick={() => {
          onComplete()
          completeChecklistItem(GettingStartedChecklistSettings.TriedCopilot)
        }}
        data-testid={`stepper-cta-${index}`}
      >
        Start chat
      </LinkButton>
    ),
    analytics: {
      category: 'zero_user_dashboard',
      action: 'click.getting_started.try_copilot',
    },
  },
  {
    title: 'Create your first repository',
    description:
      'Repositories are where your projects live on GitHub and are the main tool used to collaborate with others. ',
    ctaLabel: 'Create repository',
    href: '/new',
    autoComplete: true,
    analytics: {
      category: 'zero_user_dashboard',
      action: 'click.getting_started.create_repo',
    },
  },
]

const completeChecklistItem = (item: string) => {
  updateSetting(item, true)
}

export const NewUserGettingStartedChecklist = ({checklist, dismissed}: NewUserGettingStartedChecklistProps) => {
  const [isDismissed, setIsDismissed] = useState<boolean>(dismissed)

  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const handleDismiss = () => {
    setIsDismissed(true)
    updateSetting(DashboardDismissalSettings.GettingStarted, true)

    sendClickAnalyticsEvent({
      category: 'zero_user_dashboard',
      action: 'click.getting_started.dismiss',
    })
  }

  const isComplete = Object.values(checklist).every(Boolean)

  return isDismissed ? null : (
    <section aria-labelledby="checklist-heading" data-testid="getting-started-checklist-section">
      {isComplete ? (
        <ChecklistComplete onDismiss={handleDismiss} />
      ) : (
        <GettingStarted
          stepMetadata={gettingStartedSteps}
          dismissed={false}
          checklist={[checklist.has_customized_account, checklist.has_tried_copilot, checklist.has_created_repo]}
          /* We do not need this functionality, but it is here due to multiple implementation of this component */
          onChecklistChange={() => {}}
          onDismiss={handleDismiss}
          dismissText="Remove from dashboard"
          dashboardChecklist
        />
      )}
    </section>
  )
}

export default NewUserGettingStartedChecklist
