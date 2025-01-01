import {useContext} from 'react'

import {Button, Grid, Text} from '@primer/react-brand'

import {ContentfulSectionIntro} from '@github-ui/swp-core/components/contentful/ContentfulSectionIntro'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import type {GenericGroup, GenericContent, GenericSectionWithIds} from '../../../../../brand/lib/types/contentful'

import {PlanTypeContext} from '../../_context/PlanTypeContext'

import {PlanTypeSegmentedControl} from '../../_components/PlanTypeSegmentedControl'
import {PricingPlans} from '../../_components/PricingPlans/PricingPlans'
import IdeList from '../../_components/IdeList'

type Props = {
  contentfulContent: GenericSectionWithIds
}

export function PricingSection(props: Props) {
  const {contentfulContent} = props

  const {sectionIntro} = contentfulContent.fields

  const {featuresCopilotPricingOptions, featuresCopilotPricingSectionIdeList} = contentfulContent.ids as {
    featuresCopilotPricingOptions: GenericGroup
    featuresCopilotPricingSectionIdeList: GenericContent
  }

  const ideListCtaLink = featuresCopilotPricingSectionIdeList.fields.links?.at(0)

  const {planType, setPlanType} = useContext(PlanTypeContext)

  return (
    <Grid as="section" id="pricing">
      <Grid.Column span={12}>
        {sectionIntro ? <ContentfulSectionIntro component={sectionIntro} fullWidth headingSize="3" /> : null}

        <div className="d-flex flex-justify-center px-2 mb-7">
          <PlanTypeSegmentedControl value={planType} onChange={setPlanType} />
        </div>

        {featuresCopilotPricingOptions ? <PricingPlans contentfulContent={featuresCopilotPricingOptions} /> : null}

        {featuresCopilotPricingSectionIdeList ? (
          <div className="lp-Pricing-ctaBlock">
            <Text as="p" size="200" variant="muted" weight="medium" align="center" className="mb-5">
              {featuresCopilotPricingSectionIdeList.fields.heading}
            </Text>

            <IdeList type="small" location="pricing-cards" />

            {ideListCtaLink ? (
              <div className="d-flex flex-justify-center mt-7">
                <Button
                  as="a"
                  href={ideListCtaLink.fields.href}
                  size="medium"
                  hasArrow={false}
                  variant="subtle"
                  {...getAnalyticsEvent({
                    action: ideListCtaLink.fields.text,
                    tag: 'button',
                    context: 'ide_list',
                    location: 'cta',
                  })}
                >
                  {ideListCtaLink.fields.text}
                </Button>
              </div>
            ) : null}
          </div>
        ) : null}
      </Grid.Column>
    </Grid>
  )
}

export default PricingSection
