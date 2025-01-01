import {ThemeProvider} from '@primer/react-brand'

import Hero from './components/sections/Hero/Hero'
import Features from './components/sections/Features/Features'
import Testimonials from './components/sections/Testimonials/Testimonials'
import GetStarted from './components/sections/GetStarted/GetStarted'
import CtaBanner from './components/sections/CtaBanner/CtaBanner'
import AdditionalResources from './components/sections/AdditionalResources/AdditionalResources'
import Faq from './components/sections/Faq/Faq'

export default function CopilotExtensionsIndex() {
  return (
    <ThemeProvider colorMode="dark" className="fp-hasFontSmoothing">
      <Hero />
      <Features />
      <Testimonials />
      <GetStarted />
      <CtaBanner />
      <AdditionalResources />
      <Faq />
    </ThemeProvider>
  )
}
