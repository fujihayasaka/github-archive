import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {sendEvent} from '@github-ui/hydro-analytics'
import {Banner} from '@primer/react/experimental'
import {useEffect, useState} from 'react'

interface TrialSuccessBannerProps {
  onDismiss: () => void
  className?: string
}

export function useTrialSuccessBannerVisibility() {
  const [isVisible, setIsVisible] = useState<boolean>(() => {
    return copilotLocalStorage.getTrialSuccessBannerFlag() ?? false
  })

  useEffect(() => {
    const isBannerVisible = copilotLocalStorage.getTrialSuccessBannerFlag() ?? false
    setIsVisible(isBannerVisible)
  }, [])

  const handleDismiss = () => {
    copilotLocalStorage.removeTrialSuccessBannerFlag()
    setIsVisible(false)
  }

  return {
    visible: isVisible,
    onDismiss: handleDismiss,
  }
}

export function TrialSuccessBanner({onDismiss, className}: TrialSuccessBannerProps) {
  const {visible, onDismiss: handleDismiss} = useTrialSuccessBannerVisibility()

  if (!visible) return null

  return (
    <div className={className}>
      <Banner
        variant="success"
        title="Copilot Pro trial activated"
        description="Your 30-day Copilot Pro trial is now active."
        hideTitle
        onDismiss={() => {
          handleDismiss()
          onDismiss()
          sendEvent('dotcom_chat.activate', {
            target: 'TRIAL_SUCCESS_BANNER_DISMISS',
            mode: 'immersive',
          })
        }}
      />
    </div>
  )
}
