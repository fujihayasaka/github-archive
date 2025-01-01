import {CopilotAnimation, CopilotAnimationType} from '@github-ui/copilot-animation'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {useSafeTimeout} from '@primer/react'
import {useEffect, useState} from 'react'

export function CopilotEmptyStateAnimation({className}: {className?: string}) {
  const [animationType, setAnimationType] = useState<CopilotAnimationType>(CopilotAnimationType.Static)
  const [shouldLoop, setShouldLoop] = useState(true)
  const {safeSetTimeout} = useSafeTimeout()

  useEffect(() => {
    const timeout = safeSetTimeout(() => {
      if (copilotLocalStorage.getProPlusAnimationFlag()) {
        setAnimationType(CopilotAnimationType.Activate)
        setShouldLoop(false)
      } else {
        setAnimationType(CopilotAnimationType.Idle)
        setShouldLoop(true)
      }
    }, 1000)
    return () => clearTimeout(timeout)
  }, [safeSetTimeout])

  return (
    <div className={className}>
      <CopilotAnimation
        animationType={animationType}
        onAnimationEnd={() => {
          if (animationType === CopilotAnimationType.Activate) {
            setAnimationType(CopilotAnimationType.Idle)
            setShouldLoop(true)
            copilotLocalStorage.removeProPlusAnimationFlag()
          }
        }}
        loopAnimation={shouldLoop}
        size={48}
      />
    </div>
  )
}
