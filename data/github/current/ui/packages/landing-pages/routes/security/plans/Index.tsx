import resolveResponse from 'contentful-resolve-response'
import {clsx} from 'clsx'

import {ThemeProvider} from '@primer/react-brand'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

import {ZodSilentErrorBoundary} from '../../../components/ZodSilentErrorBoundary/ZodSilentErrorBoundary'
import {toPayload} from '../../../lib/types/payload'
import {toBrandPage, getBrandContentById} from '../../../brand/lib/types/contentful'

import Hero from './components/sections/Hero/Hero'
import Features from './components/sections/Features/Features'
import CtaBanner from './components/sections/CtaBanner/CtaBanner'
import Faq from './components/sections/Faq/Faq'

import {COPY} from './Index.data'

import SecurityStyles from './../_styles/shared.module.css'
import GlobalStyles from './styles/global.module.css'

export default function CopilotExtensionsIndex() {
  const {contentfulRawJsonResponse} = toPayload(useRoutePayload<unknown>())
  const contentfulResponse = resolveResponse(contentfulRawJsonResponse)
  const page = toBrandPage(contentfulResponse)

  const {template} = page.fields
  const {subnav, content} = template.fields

  const heroSection = getBrandContentById({content, id: 'securityPlansHeroSection'})
  const heroComponent = heroSection?.fields.content?.find(item => item.sys.contentType.sys.id === 'primerComponentHero')

  const pricingSection = getBrandContentById({content, id: 'securityPlansPricingSection'})
  const ctaBannerComponent = pricingSection?.fields.content?.find(
    item => item.sys.contentType.sys.id === 'primerComponentCtaBanner',
  )
  const faqSection = getBrandContentById({content, id: 'securityPlansFAQSection'})
  const faqGroupComponent = faqSection?.fields.content?.find(
    item => item.sys.contentType.sys.id === 'primerComponentFaqGroup',
  )

  return (
    <ZodSilentErrorBoundary>
      <ThemeProvider
        colorMode="dark"
        className={clsx(SecurityStyles.root, SecurityStyles.fontSmoothing, GlobalStyles.root)}
      >
        {heroComponent ? <Hero subnav={subnav} contentfulContent={heroComponent} {...COPY.hero} /> : null}

        <Features
          {...COPY.features}
          categories={COPY.features.categories.map(category => ({...category, aria: COPY.features.aria}))}
        />

        {ctaBannerComponent ? <CtaBanner contentfulContent={ctaBannerComponent} /> : null}

        {faqGroupComponent ? <Faq contentfulContent={faqGroupComponent} /> : null}
      </ThemeProvider>
    </ZodSilentErrorBoundary>
  )
}
