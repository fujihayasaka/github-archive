import {ThemeProvider} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

import CTA from './CTA'
import Features from './Features'
import FeaturesBento from './FeaturesBento'
import Hero from './Hero'
import Integration from './Integration'

export default function IssuesIndex() {
  return (
    <ThemeProvider colorMode="light" className="fp-hasFontSmoothing">
      <Spacer size="48px" size1012="96px" />

      <Hero />
      <Features />
      <FeaturesBento />
      <Integration />
      <CTA />
    </ThemeProvider>
  )
}
