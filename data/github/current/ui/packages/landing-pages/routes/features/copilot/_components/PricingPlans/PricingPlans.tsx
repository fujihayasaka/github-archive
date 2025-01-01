import {useContext} from 'react'

import {ContentfulPricingOptions} from '@github-ui/swp-core/components/contentful/ContentfulPricingOptions'
import type {PrimerComponentPricingOptions} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentPricingOptions'

import type {GenericGroup} from '../../../../../brand/lib/types/contentful'

import {PlanTypeContext, PLAN_TYPES} from '../../_context/PlanTypeContext'

type Props = {
  contentfulContent: GenericGroup
}

export function PricingPlans(props: Props) {
  const {contentfulContent} = props

  const individualPricingOptions =
    contentfulContent.fields.content.length > 0
      ? (contentfulContent.fields.content.at(0) as PrimerComponentPricingOptions)
      : null

  const businessPricingOptions =
    contentfulContent.fields.content.length > 1
      ? (contentfulContent.fields.content.at(1) as PrimerComponentPricingOptions)
      : null

  const {planType} = useContext(PlanTypeContext)

  return (
    <div className="mt-0 mb-8">
      {planType === PLAN_TYPES.Individual && individualPricingOptions ? (
        <div
          id="individual-plan-tab-panel"
          role="tabpanel"
          aria-labelledby="individual-plan-tab"
          className="lp-PricingPlans-plan"
        >
          <ContentfulPricingOptions component={individualPricingOptions} />
        </div>
      ) : null}

      {planType === PLAN_TYPES.Business && businessPricingOptions ? (
        <div
          id="business-plan-tab-panel"
          role="tabpanel"
          aria-labelledby="business-plan-tab"
          className="lp-PricingPlans-plan"
        >
          <ContentfulPricingOptions component={businessPricingOptions} />
        </div>
      ) : null}
    </div>
  )
}
