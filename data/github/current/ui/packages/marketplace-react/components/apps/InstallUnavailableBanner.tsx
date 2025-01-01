import {Banner} from '@primer/react/experimental'
import type {PlanInfo} from '../../types'
import checkCanInstall from '../../utilities/check-can-install'

interface InstallUnavailableBannerProps {
  planInfo: PlanInfo
}

export default function InstallUnavailableBanner({planInfo}: InstallUnavailableBannerProps) {
  const {canInstall, reason} = checkCanInstall(planInfo)
  const alreadyPurchased = planInfo.viewerHasPurchased && planInfo.viewerHasPurchasedForAllOrganizations

  if (canInstall || alreadyPurchased) {
    return null
  }

  return (
    <Banner variant="info" title="Install unavailable" hideTitle>
      <Banner.Description>
        <span id="install-unavailable-reason">{reason}</span>
      </Banner.Description>
    </Banner>
  )
}
