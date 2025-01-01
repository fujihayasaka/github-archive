import 'focus-options-polyfill'

import {PrimerFeatureFlags} from '@github-ui/react-core/PrimerFeatureFlags'
import {BaseStyles, ThemeProvider} from '@primer/react'
import {QueryClientProvider} from '@tanstack/react-query'
import {ReactQueryDevtools} from '@tanstack/react-query-devtools'
import {useEffect} from 'react'

import {App} from './app'
import {ErrorBoundary} from './components/error-boundaries/error-boundary'
import {ProjectErrorFallback} from './components/error-boundaries/project-error-fallback'
import {getThemePropsFromThemePreferences} from './helpers/color-modes'
import {getEnabledFeatures} from './helpers/feature-flags'
import {useColorSchemeFromDocumentElement} from './hooks/use-color-scheme-from-document-element'
import {RootElementContext} from './hooks/use-root-element'
import {queryClient} from './queries/query-client'

const Memex: React.FC<{
  /**
   * Children can be rendered after the 'App' Component.
   * This is only used for forcing a Rendering error
   * in dev/staging/test modes and not in the production build.
   */
  children?: React.ReactNode
  rootElement: HTMLElement
}> = ({children, rootElement}) => {
  // Temporary feature flag to enable dark load testing for Memex Without Limits
  useEffect(() => {
    const {memex_without_limits_dark_ship} = getEnabledFeatures()
    if (memex_without_limits_dark_ship) {
      const url = new URL(window.location.href)
      url.searchParams.set('dark_ship', 'true')
      fetch(url.toString())
    }
  }, [])

  const errorFallback = <ProjectErrorFallback />
  return (
    <RootElementContext.Provider value={rootElement}>
      <QueryClientProvider client={queryClient}>
        <PrimerFeatureFlags>
          <MemexThemeProvider>
            <ErrorBoundary fallback={errorFallback}>
              <App>{children}</App>
            </ErrorBoundary>
          </MemexThemeProvider>
        </PrimerFeatureFlags>
        <ReactQueryDevtools buttonPosition="bottom-right" />
      </QueryClientProvider>
    </RootElementContext.Provider>
  )
}

export default Memex

const MemexThemeProvider: React.FC<{children: React.ReactNode}> = ({children}) => {
  const themeProps = useColorSchemeFromDocumentElement()
  return (
    <ThemeProvider {...getThemePropsFromThemePreferences(themeProps)}>
      <BaseStyles display="contents">{children}</BaseStyles>
    </ThemeProvider>
  )
}
