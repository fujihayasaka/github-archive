import {isFeatureEnabled} from '@github-ui/feature-flags'
import {useEffect, useState} from 'react'

import {getSubmitTimestamp, WORKBENCH_PROMPT_SUBMIT_TIMESTAMP_UPDATED} from '../utilities/copilot-chat'

const IDLE_TIME = 25 * 60 * 1000 // 25 minutes (in ms); chosen to allow prompt submission before Codespaces auto-suspends
const DELAY = 60 * 1000 // 1 minute (in ms)

export function useSparkIdle(): boolean | null {
  const [isIdle, setIsIdle] = useState<boolean>(false)

  useEffect(() => {
    if (!isFeatureEnabled('copilot_workbench_user_limits')) {
      setIsIdle(false)
      return
    }

    // Function to check idle status
    const checkIdleStatus = () => {
      const now = Date.now()

      // Get the last activity time from local storage
      const lastActivityTime = getSubmitTimestamp()
      if (!lastActivityTime) {
        setIsIdle(false)
        return
      }

      // Calculate the time since the last activity
      const timeSinceLastActivity = now - lastActivityTime
      // Check if the time since the last activity exceeds the idle time
      setIsIdle(timeSinceLastActivity > IDLE_TIME)
    }

    // Check immediately on mount and then every minute
    checkIdleStatus()
    const intervalId = setInterval(checkIdleStatus, DELAY)

    // Clear idle when the user submits a prompt (generates an interaction)
    window.addEventListener(WORKBENCH_PROMPT_SUBMIT_TIMESTAMP_UPDATED, checkIdleStatus)

    // Cleanup after the component unmounts
    return () => {
      clearInterval(intervalId)
      window.removeEventListener(WORKBENCH_PROMPT_SUBMIT_TIMESTAMP_UPDATED, checkIdleStatus)
    }
  }, [])

  return isIdle
}
