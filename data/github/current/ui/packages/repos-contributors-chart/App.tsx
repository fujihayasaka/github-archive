import type {ReactNode} from 'react'
import {RangeSelectionProvider} from './contexts/RangeSelectionContext'
import {CalculatedMaxProvider} from './contexts/CalculatedMaxContext'

type AppProps = {
  children?: ReactNode
}

export function App({children}: AppProps) {
  return (
    <CalculatedMaxProvider>
      <RangeSelectionProvider>{children}</RangeSelectionProvider>
    </CalculatedMaxProvider>
  )
}
