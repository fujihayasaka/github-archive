import {ThemeProvider} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

import Cards from './Cards'
import CTA from './CTA'
import Features from './Features'
import Hero from './Hero'

export default function CodeSearchIndex() {
  return (
    <ThemeProvider colorMode="light" className="fp-hasFontSmoothing">
      <Spacer size="48px" size1012="96px" />

      <Hero />
      <Cards />
      <Features />
      <CTA />
    </ThemeProvider>
  )
}
