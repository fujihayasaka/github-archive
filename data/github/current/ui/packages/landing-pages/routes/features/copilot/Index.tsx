import resolveResponse from 'contentful-resolve-response'

import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ThemeProvider} from '@primer/react-brand'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import {cohortFunnelBuilder} from '../../../lib/analytics'
import {ZodSilentErrorBoundary} from '../../../components/ZodSilentErrorBoundary/ZodSilentErrorBoundary'
import {toPayload} from '../../../lib/types/payload'
import {isFeatureCopilotPage, toContainerPage, toEntryCollection} from '../../../lib/types/contentful'
import {toBrandPage, isBrandPage, getBrandContentById} from '../../../brand/lib/types/contentful'
import type {BrandPage as BrandPageType} from '../../../brand/lib/types/contentful'

import FaqSection from './_components/FaqSection'
import FeaturesSection from './_components/FeaturesSection'
import FootnotesSection from './_components/FootnotesSection'
import HeroSection from './_components/HeroSection'
import PricingSection from './_components/PricingSection'
import ResourcesSection from './_components/ResourcesSection'

export default function NewFeaturesCopilotIndex() {
  const isBrandTemplateEnabled = isFeatureEnabled('site_copilot_page_brand_template')
  const {contentfulRawJsonResponse} = toPayload(useRoutePayload<unknown>())
  const contentfulResponse = resolveResponse(contentfulRawJsonResponse)
  let page

  if (isBrandTemplateEnabled && isBrandPage(contentfulResponse)) {
    page = toBrandPage(contentfulResponse)
  } else {
    page = toContainerPage(toEntryCollection(contentfulResponse).at(0))
  }

  const {userHasOrgs} = useRoutePayload<{userHasOrgs: boolean}>()

  let {copilotProSignupPath} = useRoutePayload<{copilotProSignupPath: string}>()
  let {copilotForBusinessSignupPath} = useRoutePayload<{copilotForBusinessSignupPath: string}>()
  let {copilotEnterpriseSignupPath} = useRoutePayload<{copilotEnterpriseSignupPath: string}>()
  let {copilotBusinessContactSalesPath} = useRoutePayload<{copilotBusinessContactSalesPath: string}>()
  let {copilotEnterpriseContactSalesPath} = useRoutePayload<{copilotEnterpriseContactSalesPath: string}>()
  const {cft} = useRoutePayload<{cft: string}>()

  const withCft = cohortFunnelBuilder(cft)
  copilotProSignupPath = withCft(copilotProSignupPath, {product: 'cfi'})
  copilotForBusinessSignupPath = withCft(copilotForBusinessSignupPath, {product: 'cfb'})
  copilotEnterpriseSignupPath = withCft(copilotEnterpriseSignupPath, {product: 'ce'})
  copilotBusinessContactSalesPath = withCft(copilotBusinessContactSalesPath)
  copilotEnterpriseContactSalesPath = withCft(copilotEnterpriseContactSalesPath)
  const copilotPlansPath = withCft('/features/copilot/plans')

  if (isBrandTemplateEnabled && isBrandPage(contentfulResponse)) {
    const {template} = page.fields as BrandPageType['fields']
    const {subnav, content} = template.fields
    const faqSection = getBrandContentById({content, id: 'featuresCopilotFaqSection'})
    const faqComponent = faqSection?.fields.content?.find(
      item => item.sys.contentType.sys.id === 'primerComponentFaqGroup',
    )

    return (
      <ZodSilentErrorBoundary>
        <ThemeProvider colorMode="dark" className="lp-Copilot">
          <HeroSection
            copilotProSignupPath={copilotProSignupPath}
            copilotPlansPath={copilotPlansPath}
            subnav={subnav}
          />

          <FeaturesSection />

          <PricingSection
            copilotProSignupPath={copilotProSignupPath}
            copilotForBusinessSignupPath={copilotForBusinessSignupPath}
            copilotEnterpriseSignupPath={copilotEnterpriseSignupPath}
            copilotBusinessContactSalesPath={copilotBusinessContactSalesPath}
            copilotEnterpriseContactSalesPath={copilotEnterpriseContactSalesPath}
            userHasOrgs={userHasOrgs}
            isExpanded
          />

          <ResourcesSection />

          {faqComponent && <FaqSection contentfulContent={faqComponent} />}

          <FootnotesSection />
        </ThemeProvider>
      </ZodSilentErrorBoundary>
    )
  }

  return (
    <ThemeProvider colorMode="dark" className="lp-Copilot">
      <HeroSection copilotProSignupPath={copilotProSignupPath} copilotPlansPath={copilotPlansPath} />

      <FeaturesSection />

      <PricingSection
        copilotProSignupPath={copilotProSignupPath}
        copilotForBusinessSignupPath={copilotForBusinessSignupPath}
        copilotEnterpriseSignupPath={copilotEnterpriseSignupPath}
        copilotBusinessContactSalesPath={copilotBusinessContactSalesPath}
        copilotEnterpriseContactSalesPath={copilotEnterpriseContactSalesPath}
        userHasOrgs={userHasOrgs}
        isExpanded
      />

      <ResourcesSection />

      <ZodSilentErrorBoundary>
        {isFeatureCopilotPage(page) && <FaqSection contentfulContent={page.fields.template.fields.faqGroup} />}
      </ZodSilentErrorBoundary>

      <FootnotesSection />
    </ThemeProvider>
  )
}
