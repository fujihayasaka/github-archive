import {AriaAlert, Banner} from '@primer/react/experimental'

import {type BannerType, useActiveBanner, useSetBanner} from '../contexts/BannerContext'

const bannerMessagesMap: Record<BannerType, string> = {
  'definition.created.success': 'Property definition successfully created.',
  'definition.updated.success': 'Property definition successfully updated.',
  'definition.deleted.success': 'Property definition successfully deleted.',
  'definition.promotion.success': 'Property successfully promoted to enterprise.',
  'repos.properties.updated': 'Properties updated successfully.',
}

export function PageBanner() {
  const banner = useActiveBanner()
  const setBanner = useSetBanner()

  if (!banner) return null

  const message = bannerMessagesMap[banner]

  return (
    <Banner
      title="Property update information"
      variant="success"
      onDismiss={() => setBanner(null)}
      hideTitle
      className="mb-3"
      description={<AriaAlert>{message}</AriaAlert>}
    />
  )
}
