import {useCallback, useMemo, useState} from 'react'
import {InstallSection} from './InstallSection'
import {TermsOfService} from './TermsOfService'
import styles from '../../../marketplace.module.css'
import type {PlanInfo} from '../../../types'
import type {AppListing} from '@github-ui/marketplace-common'
import ListingBodySection from '../../ListingBodySection'
import PlansRadioGroup from './PlansRadioGroup'

type Props = {
  planInfo: PlanInfo
  listing: AppListing
}

export function Plans({planInfo, listing}: Props) {
  const [selectedPlanId, setSelectedPlanId] = useState(planInfo.selectedPlanId)

  const onPlanChange = useCallback((planId: string) => {
    setSelectedPlanId(planId)
  }, [])

  const selectedPlan = useMemo(() => {
    return planInfo.plans.find(plan => plan.id === selectedPlanId)
  }, [planInfo.plans, selectedPlanId])

  return (
    <ListingBodySection title="Plans and pricing" data-testid="pricing" id="pricing-and-setup">
      <div
        className={`${styles['marketplace-content-container']} ${styles['marketplace-content-container--less-padding']}`}
      >
        <PlansRadioGroup planInfo={planInfo} onPlanChange={onPlanChange} selectedPlanId={selectedPlanId} />
        <InstallSection planInfo={planInfo} listing={listing} selectedPlan={selectedPlan} />
      </div>
      <TermsOfService planInfo={planInfo} plan={selectedPlan} listing={listing} />
    </ListingBodySection>
  )
}
