import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {EditorMenu} from '@github-ui/global-copilot-menu/EditorMenu'
import GettingStarted from '@github-ui/nux-dashboard-refresh/components/GettingStarted'
import type {StepData} from '@github-ui/nux-dashboard-refresh/components/Stepper'
import safeStorage from '@github-ui/safe-storage'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {CopilotIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import {useEffect, useState} from 'react'

import styles from './CopilotFreeUserChecklist.module.css'
import {sendEvent, type SendEventContext} from '@github-ui/hydro-analytics'

export interface CopilotFreeUserChecklistProps {
  dismissed: boolean
  checklistState: boolean[]
  timeKey: number
}

interface SessionState {
  checklist: boolean[]
  storedTime: number
}

const sessionStorageKey = 'copilot_settings_free_user_checklist'
const analyticsMenuLocation = 'copilot_settings_free_user_checklist'

type EventName = 'completed' | 'dismiss' | 'step_complete' | 'view'
const trackEvent = (eventName: EventName, properties?: SendEventContext) => {
  sendEvent(`copilot.free_user_checklist.${eventName}`, properties)
}

const handleIcebreakerClick = (inputMessage: string) => {
  copilotLocalStorage.setEntrypointMessage(inputMessage)
  window.location.href = '/copilot'
}

const submitDismiss = async () => {
  const data = new FormData()
  data.set('copilot_free_user_checklist_dismissed', 'true')

  await verifiedFetch('/github-copilot/preferences', {
    method: 'PUT',
    body: data,
  })

  trackEvent('dismiss')
}

const trackStepComplete = (stepIndex: number) => {
  trackEvent('step_complete', {step: stepIndex + 1})
}

const submitChecklist = async (checklist: boolean[], storedTime: number) => {
  const data = new FormData()
  const safeSessionStorage = safeStorage('sessionStorage')
  data.set('copilot_free_user_checklist', JSON.stringify(checklist))
  await verifiedFetch('/github-copilot/preferences', {
    method: 'PUT',
    body: data,
  })

  safeSessionStorage.setItem(sessionStorageKey, JSON.stringify({checklist, storedTime}))

  const allStepsCompleted = checklist.every(step => step)
  if (allStepsCompleted) {
    trackEvent('completed')
  }
}

const gettingStartedSteps: StepData[] = [
  {
    title: 'Install Copilot in your editor',
    description: 'Ask about coding problems and get code completions while you work.',
    customCta: ({onComplete}) => (
      <EditorMenu menuLocation={analyticsMenuLocation} mode="copilot_settings" onButtonClick={onComplete} />
    ),
  },
  {
    title: 'Chat with Copilot anywhere',
    description: ({onComplete}) => (
      <>
        Open{' '}
        <span className="icon">
          <CopilotIcon />
        </span>{' '}
        Copilot chat in the navigation from anywhere on GitHub. Try asking{' '}
        <Link
          className={styles.icebreakerLink}
          data-testid="free-checklist-icebreaker-link"
          inline
          onClick={() => {
            onComplete()
            handleIcebreakerClick('what can I do with Copilot?')
          }}
        >
          &ldquo;what can I do with Copilot?&rdquo;
        </Link>{' '}
        to get started.
      </>
    ),
    ctaLabel: 'Go to Copilot',
    href: '/copilot',
  },
  {
    title: 'Start building with Copilot',
    description: 'Learn how to build with Copilot in Visual Studio Code or Visual Studio.',
    ctaLabel: 'Get started',
    href: 'https://docs.github.com/copilot/using-github-copilot/best-practices-for-using-github-copilot',
  },
]

export function CopilotFreeUserChecklist({dismissed, checklistState, timeKey}: CopilotFreeUserChecklistProps) {
  const safeSessionStorage = safeStorage('sessionStorage')
  const contents = safeSessionStorage.getItem(sessionStorageKey)
  const [loaded, setLoaded] = useState(false)

  let fetchedChecklist
  if (contents === null) {
    fetchedChecklist = checklistState
  } else {
    try {
      const {checklist, storedTime} = JSON.parse(contents) as SessionState
      fetchedChecklist = storedTime === timeKey ? checklist : checklistState
    } catch {
      setLoaded(false)
      throw new Error('free user checklist: failed to parse session storage data')
    }
  }

  useEffect(() => {
    trackEvent('view')
    setLoaded(true)
  }, [])

  return (
    <div data-testid="copilot-free-user-checklist">
      {loaded && (
        <GettingStarted
          stepMetadata={gettingStartedSteps}
          dismissed={dismissed}
          onDismiss={submitDismiss}
          checklist={fetchedChecklist}
          onChecklistChange={checklist => submitChecklist(checklist, timeKey)}
          trackStepComplete={trackStepComplete}
          largeHeader
        />
      )}
    </div>
  )
}
