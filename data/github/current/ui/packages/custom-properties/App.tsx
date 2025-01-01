import type {PropsWithChildren} from 'react'

import {PageFlash} from './components/PageFlash'
import {FlashProvider} from './contexts/FlashContext'

export function App({children}: PropsWithChildren) {
  return (
    <FlashProvider>
      <PageFlash />
      {children}
    </FlashProvider>
  )
}
