import type {PropsWithChildren} from 'react'

import {PageBanner} from './components/PageBanner'
import {BannerProvider} from './contexts/BannerContext'

export function App({children}: PropsWithChildren) {
  return (
    <BannerProvider>
      <PageBanner />
      {children}
    </BannerProvider>
  )
}
