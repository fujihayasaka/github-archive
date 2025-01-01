import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {RenderPhaseProvider} from '@github-ui/render-phase-provider'
import {ToastContextProvider} from '@github-ui/toast/ToastContext'
import type {ReactNode} from 'react'
// eslint-disable-next-line no-restricted-imports
import {ThemeProvider} from '@primer/react'
import {QueryClientProvider} from '@tanstack/react-query'
import {PrimerFeatureFlags} from './PrimerFeatureFlags'
import {getQueryClient} from './query-client'
import useColorModes from './use-color-modes'
import {IsDataRouterEnabledContextProvider} from './future/IsDataRouterEnabled'

interface Props {
  appName: string
  children?: ReactNode
  wasServerRendered: boolean
  dataRouterEnabled: boolean
}

const metadata = {}

/**
 * This component provides the _base_ context for both apps and partials.
 * It should provide everything needed to render with styles, themes, and i18n.
 */
export function BaseProviders({appName, children, wasServerRendered, dataRouterEnabled}: Props) {
  const {colorMode, dayScheme, nightScheme} = useColorModes()

  const queryClient = getQueryClient()

  return (
    <QueryClientProvider client={queryClient}>
      <RenderPhaseProvider wasServerRendered={wasServerRendered}>
        <AnalyticsProvider appName={appName} category="" metadata={metadata}>
          <PrimerFeatureFlags>
            <ThemeProvider colorMode={colorMode} dayScheme={dayScheme} nightScheme={nightScheme} preventSSRMismatch>
              <IsDataRouterEnabledContextProvider enabled={dataRouterEnabled}>
                <ToastContextProvider>{children}</ToastContextProvider>
              </IsDataRouterEnabledContextProvider>
            </ThemeProvider>
          </PrimerFeatureFlags>
        </AnalyticsProvider>
      </RenderPhaseProvider>
    </QueryClientProvider>
  )
}
