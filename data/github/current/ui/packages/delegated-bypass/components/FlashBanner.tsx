import {useEffect, useRef} from 'react'
import {
  useDelegatedBypassBanner,
  useDelegatedBypassSetBanner,
  type Banner,
} from '../contexts/DelegatedBypassBannerContext'
import {Banner as PrimerBanner, type BannerProps} from '@primer/react/experimental'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

const VARIANT_MAP: Record<Banner['variant'], Extract<BannerProps['variant'], 'success' | 'critical'>> = {
  success: 'success',
  danger: 'critical',
}

export function FlashBanner() {
  const banner = useDelegatedBypassBanner()
  const setBanner = useDelegatedBypassSetBanner()
  const delegatedBypassBannerEnhancements = useFeatureFlag('delegated_bypass_banner_enhancements')
  const flashRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    if (delegatedBypassBannerEnhancements) {
      flashRef.current?.focus()
    }
  }, [banner, flashRef, delegatedBypassBannerEnhancements])

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
      className={delegatedBypassBannerEnhancements ? 'm-2' : ''}
      ref={flashRef}
    />
  )
}
