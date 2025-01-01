import resolveResponse from 'contentful-resolve-response'

import {ThemeProvider, Box} from '@primer/react-brand'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ContentfulSubnav} from '@github-ui/swp-core/components/contentful/ContentfulSubnav'

import {ZodSilentErrorBoundary} from '../../../components/ZodSilentErrorBoundary/ZodSilentErrorBoundary'
import {toPayload} from '../../../lib/types/payload'
import {toBrandPage, getBrandContentById} from '../../../brand/lib/types/contentful'

import HeroSection from './sections/Hero/Hero'
import FeaturesSection from './sections/Features/Features'
import PricingSection from './sections/Pricing/Pricing'
import ResourcesSection from './sections/Resources/Resources'
import FaqSection from './sections/Faq/Faq'

import SecurityStyles from '../_styles/shared.module.css'

export default function SecurityAdvancedSecurityIndex() {
  const {contentfulRawJsonResponse} = toPayload(useRoutePayload<unknown>())
  const contentfulResponse = resolveResponse(contentfulRawJsonResponse)
  const page = toBrandPage(contentfulResponse)

  const {template} = page.fields
  const {subnav, content} = template.fields

  const faqSection = getBrandContentById({content, id: 'securityAdvancedSecurityFaqSection'})
  const faqGroupComponent = faqSection?.fields.content?.find(
    item => item.sys.contentType.sys.id === 'primerComponentFaqGroup',
  )

  return (
    <ZodSilentErrorBoundary>
      <ThemeProvider colorMode="dark" className="lp-Security lp-has-fontSmoothing lp-textWrap--pretty">
        <Box className={SecurityStyles['SubNav__spacer']} />
        {subnav ? <ContentfulSubnav component={subnav} linkVariant="default" /> : null}

        <HeroSection />
        <FeaturesSection />
        <PricingSection />
        <ResourcesSection />

        {faqGroupComponent ? <FaqSection contentfulContent={faqGroupComponent} /> : null}
      </ThemeProvider>
    </ZodSilentErrorBoundary>
  )
}
