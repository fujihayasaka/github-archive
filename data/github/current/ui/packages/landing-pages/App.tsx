import {ThemeProvider} from '@primer/react-brand'
import type React from 'react'
import {useMemo} from 'react'

import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {ContentfulFormContext} from '@github-ui/swp-core/components/contentful/ContentfulForm'
import {OctocaptchaContext} from '@github-ui/swp-core/components/forms/OctocaptchaContext'

import {ErrorBoundary} from './components/ErrorBoundary/ErrorBoundary'

/**
 * The App component is used to render content which should be present on _all_ routes within this app
 */
export function App(props: {children?: React.ReactNode}) {
  /**
   * The app payload may be null in instances where we're using the landing-pages React
   * app from locations other than the landing_pages_controller.
   */
  const payload = useAppPayload<{marketingFormsApiHost?: string; octocaptchaHost?: string} | null>()

  const octocaptchaCtx = useMemo(
    () => ({hostName: payload?.octocaptchaHost ?? '', originPage: 'marketing_forms'}),
    [payload?.octocaptchaHost],
  )

  const contentfulFormCtx = useMemo(
    () => ({marketingFormsApiHost: payload?.marketingFormsApiHost}),
    [payload?.marketingFormsApiHost],
  )

  return (
    <ErrorBoundary>
      <ContentfulFormContext.Provider value={contentfulFormCtx}>
        <OctocaptchaContext.Provider value={octocaptchaCtx}>
          <ThemeProvider dir="ltr">{props.children}</ThemeProvider>
        </OctocaptchaContext.Provider>
      </ContentfulFormContext.Provider>
    </ErrorBoundary>
  )
}
