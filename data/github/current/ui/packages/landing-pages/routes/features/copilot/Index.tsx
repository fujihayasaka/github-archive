import resolveResponse from 'contentful-resolve-response'

import {ThemeProvider, Grid} from '@primer/react-brand'

import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import {ContentfulInlineFootnotesList} from '@github-ui/swp-core/components/contentful/ContentfulInlineFootnotesList'
import {FootnotesProvider} from '@github-ui/swp-core/components/contentful/FootnotesContext'

import {ZodSilentErrorBoundary} from '../../../components/ZodSilentErrorBoundary/ZodSilentErrorBoundary'
import {toPayload} from '../../../lib/types/payload'
import {toBrandPage} from '../../../brand/lib/types/contentful'
import type {GenericSectionWithIds} from '../../../brand/lib/types/contentful'

import {FaqSection} from './_sections/FaqSection/FaqSection'
import {FeaturesSection} from './_sections/FeaturesSection/FeaturesSection'
import {HeroSection} from './_sections/HeroSection/HeroSection'
import {IntegrationsSection} from './_sections/IntegrationsSection/IntegrationsSection'
import {PricingSection} from './_sections/PricingSection/PricingSection'
import {ResourcesSection} from './_sections/ResourcesSection/ResourcesSection'
import type {IdeLinks} from './_components/IdeCta/IdeCta'

import {PlanTypeContextProvider} from './_context/PlanTypeContext'

export default function FeaturesCopilotIndex() {
  const {contentfulRawJsonResponse, copilotIdeDeepLinks} = toPayload(useRoutePayload<unknown>())
  const contentfulResponse = resolveResponse(contentfulRawJsonResponse)
  const page = toBrandPage(contentfulResponse)

  const isPostMsBuildLaunch = isFeatureEnabled('site_msbuild_launch')
  const shouldHideIntegrationsSection = isFeatureEnabled('site_msbuild_hide_integrations')

  const {template} = page.fields
  const {subnav} = template.fields
  const {
    featuresCopilotFaqSection,
    featuresCopilotFeaturesSection,
    featuresCopilotHeroSection,
    featuresCopilotIntegrationsSection,
    featuresCopilotPricingSection,
    featuresCopilotResourcesSection,
  } = page.ids as {
    featuresCopilotFaqSection: GenericSectionWithIds
    featuresCopilotFeaturesSection: GenericSectionWithIds
    featuresCopilotHeroSection: GenericSectionWithIds
    featuresCopilotIntegrationsSection: GenericSectionWithIds
    featuresCopilotPricingSection: GenericSectionWithIds
    featuresCopilotResourcesSection: GenericSectionWithIds
  }

  return (
    <ZodSilentErrorBoundary>
      <FootnotesProvider>
        <PlanTypeContextProvider>
          <ThemeProvider colorMode="dark" className="lp-Copilot">
            {featuresCopilotHeroSection ? (
              <HeroSection
                contentfulContent={featuresCopilotHeroSection}
                subnav={subnav}
                copilotIdeDeepLinks={copilotIdeDeepLinks as IdeLinks}
              />
            ) : null}

            {featuresCopilotFeaturesSection ? (
              <FeaturesSection contentfulContent={featuresCopilotFeaturesSection} />
            ) : null}

            {featuresCopilotPricingSection ? (
              <PricingSection contentfulContent={featuresCopilotPricingSection} />
            ) : null}

            {/* The integrations section is hidden for the MS Build launch, or via its independent feature flag is enabled */}
            {/* This is a temporary solution until we remove the integrations section from Contentful */}
            {(!isPostMsBuildLaunch || !shouldHideIntegrationsSection) && featuresCopilotIntegrationsSection ? (
              <IntegrationsSection contentfulContent={featuresCopilotIntegrationsSection} />
            ) : null}

            {featuresCopilotResourcesSection ? (
              <ResourcesSection contentfulContent={featuresCopilotResourcesSection} />
            ) : null}

            {featuresCopilotFaqSection ? <FaqSection contentfulContent={featuresCopilotFaqSection} /> : null}

            <Grid>
              <Grid.Column span={12}>
                <ContentfulInlineFootnotesList className="pt-0" />
              </Grid.Column>
            </Grid>
          </ThemeProvider>
        </PlanTypeContextProvider>
      </FootnotesProvider>
    </ZodSilentErrorBoundary>
  )
}
