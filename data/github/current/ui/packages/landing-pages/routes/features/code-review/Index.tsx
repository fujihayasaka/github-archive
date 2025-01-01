import {ThemeProvider} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

import Discuss from './Discuss'
import Features from './Features'
import Hero from './Hero'
import Quality from './Quality'

export default function CodeReviewIndex() {
  return (
    <ThemeProvider colorMode="light" className="fp-hasFontSmoothing">
      <Spacer size="48px" size1012="96px" />

      <Hero />
      <Features />
      <Discuss />
      <Quality />
    </ThemeProvider>
  )
}
