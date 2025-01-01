import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {RelayEnvironmentProvider} from 'react-relay'
import type {PropsWithChildren} from 'react'
import {NavigateWithFlashBannerProvider} from '../features/NavigateWithFlashBanner'

const relayEnv = relayEnvironmentWithMissingFieldHandlerForNode()

export function RouteProviders({children}: PropsWithChildren) {
  return (
    <NavigateWithFlashBannerProvider>
      <RelayEnvironmentProvider environment={relayEnv}>{children} </RelayEnvironmentProvider>
    </NavigateWithFlashBannerProvider>
  )
}
