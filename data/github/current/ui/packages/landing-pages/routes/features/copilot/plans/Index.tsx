import resolveResponse from 'contentful-resolve-response'

import {ThemeProvider, Box, Grid} from '@primer/react-brand'

import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

import {ContentfulSubnav} from '@github-ui/swp-core/components/contentful/ContentfulSubnav'
import {ContentfulInlineFootnotesList} from '@github-ui/swp-core/components/contentful/ContentfulInlineFootnotesList'
import {FootnotesProvider} from '@github-ui/swp-core/components/contentful/FootnotesContext'

import {ZodSilentErrorBoundary} from '../../../../components/ZodSilentErrorBoundary/ZodSilentErrorBoundary'
import {toPayload} from '../../../../lib/types/payload'
import {toBrandPage} from '../../../../brand/lib/types/contentful'
import type {GenericSectionWithIds} from '../../../../brand/lib/types/contentful'

import {FaqSection} from '../_sections/FaqSection/FaqSection'

import {PlanTypeContextProvider} from '../_context/PlanTypeContext'

import {CompareTable} from './CompareTable'
import {CtaSection} from './CtaSection'
import {HeroSection} from './HeroSection'

export default function FeaturesCopilotPlansIndex() {
  const {contentfulRawJsonResponse} = toPayload(useRoutePayload<unknown>())
  const contentfulResponse = resolveResponse(contentfulRawJsonResponse)
  const page = toBrandPage(contentfulResponse)

  const {template} = page.fields
  const {subnav} = template.fields
  const {
    featuresCopilotFaqSection,
    featuresCopilotPlansComparison,
    featuresCopilotPlansCtaSection,
    featuresCopilotPlansHeroSection,
  } = page.ids as {
    featuresCopilotFaqSection: GenericSectionWithIds
    featuresCopilotPlansComparison: GenericSectionWithIds
    featuresCopilotPlansCtaSection: GenericSectionWithIds
    featuresCopilotPlansHeroSection: GenericSectionWithIds
  }

  return (
    <ZodSilentErrorBoundary>
      <FootnotesProvider>
        <PlanTypeContextProvider>
          <ThemeProvider colorMode="dark" className="lp-Copilot position-relative">
            <Box className="lp-SubNav-spacer" />

            {subnav ? (
              <ContentfulSubnav component={subnav} className="lp-Hero-subnav lp-Hero-subnav--highContrast" />
            ) : null}

            {featuresCopilotPlansHeroSection ? (
              <HeroSection contentfulContent={featuresCopilotPlansHeroSection} />
            ) : null}

            {featuresCopilotPlansComparison ? (
              <CompareTable contentfulContent={featuresCopilotPlansComparison} />
            ) : null}

            {featuresCopilotPlansCtaSection ? <CtaSection contentfulContent={featuresCopilotPlansCtaSection} /> : null}

            {featuresCopilotFaqSection ? <FaqSection contentfulContent={featuresCopilotFaqSection} /> : null}

            <Grid>
              <Grid.Column span={12}>
                <ContentfulInlineFootnotesList />
              </Grid.Column>
            </Grid>
          </ThemeProvider>
        </PlanTypeContextProvider>
      </FootnotesProvider>
    </ZodSilentErrorBoundary>
  )
}
