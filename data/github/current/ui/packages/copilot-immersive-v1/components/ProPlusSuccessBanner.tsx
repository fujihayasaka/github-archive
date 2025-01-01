import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {sendEvent} from '@github-ui/hydro-analytics'
import {Banner} from '@primer/react/experimental'
import {useState} from 'react'

interface ProPlusSuccessBannerProps {
  onDismiss: () => void
  className?: string
}

export function useProPlusSuccessBannerVisibility() {
  const [isVisible, setIsVisible] = useState<boolean>(() => {
    return copilotLocalStorage.getProPlusSuccessBannerFlag() ?? false
  })

  const handleDismiss = () => {
    copilotLocalStorage.removeProPlusSuccessBannerFlag()
    // If user signed up for trial then pro+, we need to clear both flags.
    copilotLocalStorage.removeTrialSuccessBannerFlag()
    setIsVisible(false)
  }

  return {
    visible: isVisible,
    onDismiss: handleDismiss,
  }
}

export function ProPlusSuccessBanner({onDismiss, className}: ProPlusSuccessBannerProps) {
  return (
    <div className={className}>
      <Banner
        variant="success"
        title="Copilot Pro+ activated"
        description="Your Copilot Pro+ subscription is now active."
        hideTitle
        onDismiss={() => {
          onDismiss()
          sendEvent('dotcom_chat.activate', {
            target: 'PRO_PLUS_SUCCESS_BANNER_DISMISS',
            mode: 'immersive',
          })
        }}
      />
    </div>
  )
}
