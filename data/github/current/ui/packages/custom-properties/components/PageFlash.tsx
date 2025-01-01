import {AriaAlert, Banner} from '@primer/react/experimental'

import {type FlashType, useActiveFlash, useSetFlash} from '../contexts/FlashContext'

const flashMessagesMap: Record<FlashType, string> = {
  'definition.created.success': 'Property definition successfully created.',
  'definition.updated.success': 'Property definition successfully updated.',
  'definition.deleted.success': 'Property definition successfully deleted.',
  'definition.promotion.success': 'Property successfully promoted to enterprise.',
  'repos.properties.updated': 'Properties updated successfully.',
}

export function PageFlash() {
  const flash = useActiveFlash()
  const setFlash = useSetFlash()

  if (!flash) return null

  const message = flashMessagesMap[flash]

  return (
    <Banner
      title="Property update information"
      variant="success"
      onDismiss={() => setFlash(null)}
      hideTitle
      className="mb-3"
      description={<AriaAlert>{message}</AriaAlert>}
    />
  )
}
