import {useMemo, useState} from 'react'
import {PlanForm} from './PlanForm'
import type {PlanInfo, Plan} from '../../../types'
import type {AppListing} from '@github-ui/marketplace-common'
import checkCanInstall from '../../../utilities/check-can-install'

type Props = {
  planInfo: PlanInfo
  listing: AppListing
  selectedPlan?: Plan
}

export function InstallSection({planInfo, listing, selectedPlan}: Props) {
  const [selectedAccount, setSelectedAccount] = useState(planInfo.selectedAccount || planInfo.currentUser?.displayLogin)
  const installSection = useMemo(() => {
    const {canInstall, reason} = checkCanInstall(planInfo)
    if (!canInstall) {
      return <div className="pt-3">{reason}</div>
    } else if (selectedPlan) {
      return (
        <PlanForm
          planInfo={planInfo}
          listing={listing}
          plan={selectedPlan}
          selectedAccount={selectedAccount}
          onAccountSelect={setSelectedAccount}
        />
      )
    }
  }, [planInfo, selectedPlan, listing, selectedAccount, setSelectedAccount])

  return installSection && <div data-testid="install-section">{installSection}</div>
}
