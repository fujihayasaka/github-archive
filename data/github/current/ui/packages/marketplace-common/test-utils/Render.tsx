import {render, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {SearchAndFilterProviderStack} from '../contexts/SearchAndFilterProviderStack'
import {getIndexRoutePayload} from './mock-data'
import {ThemeProvider} from '@primer/react'
import type {IndexPayload} from '../types'

export const renderWithFilterContext = (
  component: React.ReactNode,
  mockOverrides: Partial<IndexPayload> = {},
  options?: Omit<TestRenderOptions, 'routePayload'>,
) => {
  const routePayload = getIndexRoutePayload(mockOverrides)
  return render(
    <SearchAndFilterProviderStack>
      <ThemeProvider>{component}</ThemeProvider>
    </SearchAndFilterProviderStack>,
    {routePayload, ...options},
  )
}
