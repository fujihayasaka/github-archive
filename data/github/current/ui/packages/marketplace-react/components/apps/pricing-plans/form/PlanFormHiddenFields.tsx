import {usePlanForm} from './PlanFormContext'

export default function PlanFormHiddenFields() {
  const {planInfo, listing, canReinstall, skipOrderReview, authToken} = usePlanForm()
  return (
    <>
      <input type="hidden" name="quantity" id="quantity" value="1" data-testid="quantity" />
      {(skipOrderReview || canReinstall) && (
        // eslint-disable-next-line github/authenticity-token
        <input type="hidden" name="authenticity_token" value={authToken} data-testid="csrf-token" />
      )}
      {skipOrderReview && (
        <>
          {planInfo.canSignEndUserAgreement && planInfo.endUserAgreement && (
            <>
              <input
                type="hidden"
                name="marketplace_listing_id"
                id="marketplace_listing_id"
                value={listing.id}
                data-testid="marketplace-listing-id"
              />
              <input
                type="hidden"
                name="marketplace_agreement_id"
                id="marketplace_agreement_id"
                value={planInfo.endUserAgreement.id}
                data-testid="marketplace-agreement-id"
              />
            </>
          )}
        </>
      )}
    </>
  )
}
