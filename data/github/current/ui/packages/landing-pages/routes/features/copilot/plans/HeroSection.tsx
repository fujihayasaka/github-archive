import {useContext} from 'react'

import {Hero, Grid, Text} from '@primer/react-brand'

import type {GenericGroup, GenericContent, GenericSectionWithIds} from '../../../../brand/lib/types/contentful'

import {PlanTypeContext} from '../_context/PlanTypeContext'

import {PlanTypeSegmentedControl} from '../_components/PlanTypeSegmentedControl'
import {PricingPlans} from '../_components/PricingPlans/PricingPlans'
import IdeList from '../_components/IdeList'

type Props = {
  contentfulContent: GenericSectionWithIds
}

export function HeroSection(props: Props) {
  const {contentfulContent} = props

  const {featuresCopilotPlansHero, featuresCopilotPlansHeroIdeList, featuresCopilotPricingOptions} =
    contentfulContent.ids as {
      featuresCopilotPlansHero: GenericContent
      featuresCopilotPlansHeroIdeList: GenericContent
      featuresCopilotPricingOptions: GenericGroup
    }

  const {planType, setPlanType} = useContext(PlanTypeContext)

  return (
    <Grid as="section" className="position-relative">
      <Grid.Column span={12}>
        {featuresCopilotPlansHero ? (
          <Hero align="center" className="pb-4">
            <Hero.Heading size="2">{featuresCopilotPlansHero.fields.heading}</Hero.Heading>
          </Hero>
        ) : null}

        <div className="d-flex flex-justify-center px-2 mb-7">
          <h2 className="visually-hidden" id="pricing-plans">
            Pricing plans
          </h2>

          <PlanTypeSegmentedControl value={planType} onChange={setPlanType} />
        </div>

        {featuresCopilotPricingOptions ? <PricingPlans contentfulContent={featuresCopilotPricingOptions} /> : null}

        <div className="mb-5">
          {featuresCopilotPlansHeroIdeList ? (
            <Text as="p" size="200" variant="muted" weight="medium" align="center" className="mb-5">
              {featuresCopilotPlansHeroIdeList.fields.heading}
            </Text>
          ) : null}

          <IdeList type="small" location="pricing-cards" />
        </div>
      </Grid.Column>
    </Grid>
  )
}
