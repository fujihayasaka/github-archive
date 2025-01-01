import {ThemeProvider} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

import Context from './Context'
import CTA from './CTA'
import FAQ from './FAQ'
import Features from './Features'
import Hero from './Hero'
import Testimonials from './Testimonials'

export default function CodespacesIndex() {
  return (
    <ThemeProvider colorMode="dark" className="fp-hasFontSmoothing fp-hasDarkGradientBorder">
      {/* Header + Subnav = 136px */}
      <Spacer size="136px" />
      <Spacer size="48px" size1012="96px" />

      <Hero />
      <Features />
      <Context />
      <Testimonials />
      <CTA />
      <FAQ />

      <Spacer size="64px" size1012="128px" />
    </ThemeProvider>
  )
}
