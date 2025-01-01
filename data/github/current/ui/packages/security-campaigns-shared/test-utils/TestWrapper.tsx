import {QueryClientProvider, type QueryClient} from '@tanstack/react-query'
import {getQueryClient} from './query-client'

export type TestWrapperProps = {
  children: React.ReactNode

  queryClient?: QueryClient
}

export function TestWrapper({children, queryClient}: TestWrapperProps) {
  const client = queryClient ?? getQueryClient()
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>
}
