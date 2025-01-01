import resolveResponse from 'contentful-resolve-response'

import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ThemeProvider, Box} from '@primer/react-brand'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {ContentfulSubnav} from '@github-ui/swp-core/components/contentful/ContentfulSubnav'

import {ZodSilentErrorBoundary} from '../../../../components/ZodSilentErrorBoundary/ZodSilentErrorBoundary'
import {toPayload} from '../../../../lib/types/payload'
import {isFeatureCopilotPage, toContainerPage, toEntryCollection} from '../../../../lib/types/contentful'
import {toBrandPage, isBrandPage, getBrandContentById} from '../../../../brand/lib/types/contentful'
import type {BrandPage as BrandPageType} from '../../../../brand/lib/types/contentful'

import CopilotSubNav from '../_components/CopilotSubNav'
import CallToAction from '../_components/CallToAction'
import PricingSection from '../_components/PricingSection'
import FootnotesSection from '../_components/FootnotesSection'
import FaqSection from '../_components/FaqSection'
import {cohortFunnelBuilder} from '../../../../lib/analytics'

import PricingBackground from '../_assets/pricing-bg.webp'
import PricingBackgroundSm from '../_assets/pricing-bg-sm.webp'

export default function NewFeaturesCopilotPlansIndex() {
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
          <div className="position-relative">
            <Box className="lp-SubNav-spacer" />
            {subnav ? (
              <ContentfulSubnav component={subnav} className="lp-Hero-subnav lp-Hero-subnav--highContrast" />
            ) : (
              <CopilotSubNav currentUrl="/features/copilot/plans" />
            )}

            <picture>
              <source srcSet={PricingBackgroundSm} media="(max-width: 767px)" />
              <img src={PricingBackground} className="position-absolute top-0 left-0 width-full height-auto" alt="" />
            </picture>

            <PricingSection
              copilotProSignupPath={copilotProSignupPath}
              copilotForBusinessSignupPath={copilotForBusinessSignupPath}
              copilotEnterpriseSignupPath={copilotEnterpriseSignupPath}
              copilotBusinessContactSalesPath={copilotBusinessContactSalesPath}
              copilotEnterpriseContactSalesPath={copilotEnterpriseContactSalesPath}
              userHasOrgs={userHasOrgs}
              isExpanded
              showLabel={false}
              className="lp-Section--hero"
              headingLevel="h1"
            />
          </div>

          <section className="lp-Section pt-5 pt-lg-8">
            <CallToAction copilotContactSalesPath={copilotBusinessContactSalesPath} />
          </section>

          {faqComponent && <FaqSection contentfulContent={faqComponent} />}

          <FootnotesSection />
        </ThemeProvider>
      </ZodSilentErrorBoundary>
    )
  }

  return (
    <ThemeProvider colorMode="dark" className="lp-Copilot">
      <div className="position-relative">
        <Box className="lp-SubNav-spacer" />
        <CopilotSubNav currentUrl="/features/copilot/plans" />

        <picture>
          <source srcSet={PricingBackgroundSm} media="(max-width: 767px)" />
          <img src={PricingBackground} className="position-absolute top-0 left-0 width-full height-auto" alt="" />
        </picture>

        <PricingSection
          copilotProSignupPath={copilotProSignupPath}
          copilotForBusinessSignupPath={copilotForBusinessSignupPath}
          copilotEnterpriseSignupPath={copilotEnterpriseSignupPath}
          copilotBusinessContactSalesPath={copilotBusinessContactSalesPath}
          copilotEnterpriseContactSalesPath={copilotEnterpriseContactSalesPath}
          userHasOrgs={userHasOrgs}
          isExpanded
          showLabel={false}
          className="lp-Section--hero"
          headingLevel="h1"
        />
      </div>

      <section className="lp-Section pt-5 pt-lg-8">
        <CallToAction copilotContactSalesPath={copilotBusinessContactSalesPath} />
      </section>

      <ZodSilentErrorBoundary>
        {isFeatureCopilotPage(page) && <FaqSection contentfulContent={page.fields.template.fields.faqGroup} />}
      </ZodSilentErrorBoundary>

      <FootnotesSection />
    </ThemeProvider>
  )
}
