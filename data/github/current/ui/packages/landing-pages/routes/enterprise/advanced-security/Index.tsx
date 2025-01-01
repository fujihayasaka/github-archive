import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

import {ThemeProvider} from '@primer/react-brand'

import EnterpriseSubNav from '../shared/SubNav'
import HeroSection from './components/HeroSection'
import EnterpriseSection from './components/EnterpriseSection'
import FeaturesSection from './components/FeaturesSection'
import PricingSection from './components/PricingSection'
import ResourcesSection from './components/ResourcesSection'
import FAQSection from './components/FAQSection'
import FootnotesSection from './components/FootnotesSection'

type EnterpriseAdvancedSecurityPayload = {
  [key: string]: unknown

  requestDemoPath: string
  heroEnterpriseTrialPath: string
  navContactSalesPath: string
  pricingContactSalesPath: string
  userMillionsFallback: string
}

export function EnterpriseAdvancedSecurityIndex() {
  const {
    requestDemoPath,
    heroEnterpriseTrialPath,
    navContactSalesPath,
    pricingContactSalesPath,
    userMillionsFallback,
    ...payload
  } = useRoutePayload<EnterpriseAdvancedSecurityPayload>()

  return (
    <ThemeProvider colorMode="dark" className="lp-Security lp-has-fontSmoothing lp-textWrap--pretty">
      <EnterpriseSubNav currentPage="/enterprise/advanced-security" />
      <HeroSection
        heroEnterpriseTrialPath={heroEnterpriseTrialPath}
        navContactSalesPath={navContactSalesPath}
        requestDemoPath={requestDemoPath}
      />
      <EnterpriseSection />
      <FeaturesSection userMillionsFallback={userMillionsFallback} />
      <PricingSection pricingContactSalesPath={pricingContactSalesPath} />
      <ResourcesSection />
      <FAQSection payload={payload} />
      <FootnotesSection />
    </ThemeProvider>
  )
}
