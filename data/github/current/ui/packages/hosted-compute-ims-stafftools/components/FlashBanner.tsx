import {Flash, type FlashProps} from '@primer/react'
import {useState} from 'react'

export interface FlashState {
  message: string
  variant: FlashProps['variant']
}

interface FlashBannerProps {
  state: FlashState | null
}

export function FlashBanner({state}: FlashBannerProps): JSX.Element | null {
  if (state === null) {
    return null
  }

  return (
    <Flash variant={state.variant} sx={{mb: 2}}>
      {state.message}
    </Flash>
  )
}

export function useFlashBannerState() {
  const [flashBanner, setFlashBanner] = useState<FlashState | null>(null)

  return {
    state: flashBanner,
    showInfo: (message: string) => setFlashBanner({message, variant: 'default'}),
    showError: (message: string) => setFlashBanner({message, variant: 'danger'}),
    hide: () => setFlashBanner(null),
  }
}
