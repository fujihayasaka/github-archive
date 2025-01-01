import type {PlanInfo, Plan} from '../../../types'
import type {AppListing} from '@github-ui/marketplace-common'

type Props = {
  planInfo: PlanInfo
  plan: Plan
  listing: AppListing
}

export function InstallHelpText({planInfo, plan, listing}: Props) {
  if (planInfo.freeTrialsUsed) {
    return <div>You’ve already used a free trial for this app</div>
  } else if (!planInfo.installationUrlRequirementMet) {
    if (planInfo.userCanEditListing) {
      return (
        <div>
          This app is not installable because it is missing{' '}
          <a href={`/marketplace/${listing.slug}/edit/description#naming_and_links`}>an installation URL</a>.
        </div>
      )
    } else {
      return null
    }
  } else if (planInfo.isBuyable) {
    return (
      <p className="mt-2 mb-0 f6">
        Next: Confirm your installation location{plan.isPaid && ' and payment information'}
      </p>
    )
  } else {
    return <p className="mt-2 mb-0 f6">You’ve already purchased this on all of your GitHub accounts</p>
  }
}
