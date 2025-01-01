import {ThemeProvider} from '@primer/react-brand'
import {clsx} from 'clsx'

import Hero from './components/sections/Hero/Hero'
import Features from './components/sections/Features/Features'
import CtaBanner from './components/sections/CtaBanner/CtaBanner'
import Faq from './components/sections/Faq/Faq'

import {COPY} from './Index.data'

import SecurityStyles from './../_styles/shared.module.css'
import GlobalStyles from './styles/global.module.css'

export default function CopilotExtensionsIndex() {
  return (
    <ThemeProvider
      colorMode="dark"
      className={clsx(SecurityStyles.root, SecurityStyles.fontSmoothing, GlobalStyles.root)}
    >
      <Hero {...COPY.hero} />
      <Features {...COPY.features} />
      <CtaBanner {...COPY.ctaBanner} />
      <Faq {...COPY.faq} />
    </ThemeProvider>
  )
}
