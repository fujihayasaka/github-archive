import {ThemeProvider} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

import Community from './Community'
import CTA from './CTA'
import Discuss from './Discuss'
import Features from './Features'
import Hero from './Hero'
import Mobile from './Mobile'

export default function DiscussionsIndex() {
  return (
    <ThemeProvider colorMode="light" className="fp-hasFontSmoothing">
      <Spacer size="48px" size1012="96px" />

      <Hero />
      <Features />
      <Discuss />
      <Mobile />
      <Community />
      <CTA />

      <Spacer size="64px" size1012="128px" />
    </ThemeProvider>
  )
}
