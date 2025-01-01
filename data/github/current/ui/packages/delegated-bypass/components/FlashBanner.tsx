import {
  useDelegatedBypassBanner,
  useDelegatedBypassSetBanner,
  type Banner,
} from '../contexts/DelegatedBypassBannerContext'
import {Banner as PrimerBanner, type BannerProps} from '@primer/react/experimental'

const VARIANT_MAP: Record<Banner['variant'], Extract<BannerProps['variant'], 'success' | 'critical'>> = {
  success: 'success',
  danger: 'critical',
}

export function FlashBanner() {
  const banner = useDelegatedBypassBanner()
  const setBanner = useDelegatedBypassSetBanner()

  if (!banner) {
    return null
  }

  const MappedVariant = VARIANT_MAP[banner.variant]

  return (
    <PrimerBanner
      variant={MappedVariant}
      onDismiss={() => setBanner()}
      title={banner.message}
      description={banner.description}
    />
  )
}
