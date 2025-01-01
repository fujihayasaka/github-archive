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
  heroContactSalesPath: string
  navContactSalesPath: string
  pricingContactSalesPath: string
}

export function EnterpriseAdvancedSecurityIndex() {
  const {requestDemoPath, heroContactSalesPath, navContactSalesPath, pricingContactSalesPath, ...payload} =
    useRoutePayload<EnterpriseAdvancedSecurityPayload>()

  return (
    <ThemeProvider colorMode="dark" className="lp-Security lp-has-fontSmoothing lp-textWrap--pretty">
      <EnterpriseSubNav />
      <HeroSection
        heroContactSalesPath={heroContactSalesPath}
        navContactSalesPath={navContactSalesPath}
        requestDemoPath={requestDemoPath}
      />
      <EnterpriseSection />
      <FeaturesSection />
      <PricingSection pricingContactSalesPath={pricingContactSalesPath} />
      <ResourcesSection />
      <FAQSection payload={payload} />
      <FootnotesSection />
    </ThemeProvider>
  )
}
