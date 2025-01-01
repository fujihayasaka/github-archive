import {QueryClient, QueryClientProvider} from '@tanstack/react-query'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {RelayEnvironmentProvider} from 'react-relay'
import type {PropsWithChildren} from 'react'
import {NavigateWithFlashBannerProvider} from '../features/NavigateWithFlashBanner'

const queryClient = new QueryClient()
const relayEnv = relayEnvironmentWithMissingFieldHandlerForNode()

export function RouteProviders({children}: PropsWithChildren) {
  return (
    <NavigateWithFlashBannerProvider>
      <QueryClientProvider client={queryClient}>
        <RelayEnvironmentProvider environment={relayEnv}>{children} </RelayEnvironmentProvider>
      </QueryClientProvider>
    </NavigateWithFlashBannerProvider>
  )
}
