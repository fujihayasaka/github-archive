import {Banner} from '@primer/react/experimental'
import {createPortal} from 'react-dom'
import type {BannerProps} from '@primer/react/experimental'

export function BannerPortal({
  message,
  variant,
  onDismiss,
}: {
  message: string
  variant: BannerProps['variant']
  onDismiss: () => void
}) {
  const container = document.getElementById('js-flash-container')

  if (!container) return null

  return createPortal(
    <Banner title="title" hideTitle variant={variant} onDismiss={onDismiss}>
      {message}
    </Banner>,
    container,
  )
}
