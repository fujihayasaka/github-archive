import {useBannerState} from '@github-ui/workbench/hooks/use-banner-state'
import {BannerType} from '@github-ui/workspace-editor/utilities/workspace-editor-types'
import {clsx} from 'clsx'
import {useEffect, useRef} from 'react'

import {ComputeLimitBanner} from './ComputeLimitBanner'
import {CopilotBillingBanner} from './CopilotBillingBanner'
import {RuntimeLimitBanner} from './RuntimeLimitBanner'
import {SparkInfraLimitBanner} from './SparkInfraLimitBanner'

export interface BannerProps {
  className?: string
}

export function Banner({className}: BannerProps) {
  const bannerRef = useRef<HTMLDivElement>(null)
  const banner = useBannerState()

  useEffect(() => {
    // only works if it's a net new render
    if (bannerRef.current) {
      const timeout = window.setTimeout(() => {
        bannerRef.current?.focus()
      }, 0)

      return () => {
        window.clearTimeout(timeout)
      }
    }
  }, [bannerRef])

  if (!banner) {
    return null
  }

  let bannerToShow: React.ReactNode | null = null
  switch (banner) {
    // Banner display order is prioritized as follows (from highest to lowest):
    // spark-infra-limit > copilot-billing > runtime-limit > compute-limit
    // This order ensures system-level and billing issues are surfaced before usage-related notices.
    // ⬇️ system states
    case BannerType.SPARK_INFRA_LIMIT:
      bannerToShow = <SparkInfraLimitBanner />
      break
    case BannerType.COPILOT_BILLING:
      bannerToShow = <CopilotBillingBanner />
      break
    // ⬇️ application states
    case BannerType.RUNTIME_LIMIT:
      bannerToShow = <RuntimeLimitBanner />
      break
    case BannerType.COMPUTE_LIMIT:
      bannerToShow = <ComputeLimitBanner />
      break
    default:
      break
  }

  return bannerToShow ? (
    <div ref={bannerRef} tabIndex={-1} className={clsx('width-full', className)}>
      {bannerToShow}
    </div>
  ) : null
}
