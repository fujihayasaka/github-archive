import {ThemeProvider} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

import Hero from './Hero'
import Features from './Features'
import Testimonials from './Testimonials'
import Pricing from './Pricing'
import CTA from './CTA'

export default function ActionsIndex() {
  return (
    <ThemeProvider colorMode="dark" className="fp-hasFontSmoothing fp-hasDarkGradientBorder">
      {/* Header + Subnav = 136px */}
      <Spacer size="136px" />
      <Spacer size="48px" size1012="96px" />

      <Hero />
      <Features />
      <Testimonials />
      <Pricing />
      <CTA />
    </ThemeProvider>
  )
}
