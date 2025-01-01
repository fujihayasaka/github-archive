import {ThemeProvider} from '@primer/react-brand'

import AISection from './components/AISection'
import AnchorNav from './components/AnchorNav'
import CTASection from './components/CTASection'
import HeroSection from './components/HeroSection'
import ReliabilitySection from './components/ReliabilitySection'
import ScaleSection from './components/ScaleSection'
import SecuritySection from './components/SecuritySection'

export default function EnterpriseIndex() {
  return (
    <ThemeProvider colorMode="dark" className="enterprise-lp enterprise-dark-bg">
      <HeroSection />

      <AnchorNav />

      <ScaleSection />
      <AISection />
      <SecuritySection />
      <ReliabilitySection />
      <CTASection />
    </ThemeProvider>
  )
}
