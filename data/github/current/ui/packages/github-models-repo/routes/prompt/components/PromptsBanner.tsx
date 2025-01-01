import {Banner as PrimerBanner} from '@primer/react/experimental'
import {usePromptsBanner} from '../contexts/PromptBannersContext'

export function PromptsBanner() {
  const {banner, setBanner} = usePromptsBanner()

  if (!banner) {
    return null
  }

  return (
    <PrimerBanner
      variant={banner.variant}
      onDismiss={() => setBanner()}
      title={banner.message}
      description={banner.description}
    />
  )
}
