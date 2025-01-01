import {ThemeProvider} from '@primer/react-brand'
import type React from 'react'
import {useMemo} from 'react'

import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {ContentfulFormContext} from '@github-ui/swp-core/components/contentful/ContentfulForm'
import {OctocaptchaContext} from '@github-ui/swp-core/components/forms/OctocaptchaContext'
import {ConsentExperienceContext} from '@github-ui/swp-core/components/forms/ConsentExperienceContext'

import type {Country} from '@github-ui/swp-core/components/forms/ConsentExperienceContext'

import {ErrorBoundary} from './components/ErrorBoundary/ErrorBoundary'

/**
 * The App component is used to render content which should be present on _all_ routes within this app
 */
export function App(props: {children?: React.ReactNode}) {
  /**
   * The app payload may be null in instances where we're using the landing-pages React
   * app from locations other than the landing_pages_controller.
   */
  const payload = useAppPayload<{
    marketingFormsApiHost?: string
    octocaptchaHost?: string
    marketingTargetedCountries: Country[]
  } | null>()

  const octocaptchaCtx = useMemo(
    () => ({hostName: payload?.octocaptchaHost ?? '', originPage: 'marketing_forms'}),
    [payload?.octocaptchaHost],
  )

  const contentfulFormCtx = useMemo(
    () => ({
      marketingFormsApiHost: payload?.marketingFormsApiHost,
      marketingTargetedCountries: payload?.marketingTargetedCountries,
    }),
    [payload?.marketingFormsApiHost, payload?.marketingTargetedCountries],
  )

  const consentExperienceCtx = useMemo(
    () => ({marketingTargetedCountries: payload?.marketingTargetedCountries ?? []}),
    [payload?.marketingTargetedCountries],
  )

  return (
    <ErrorBoundary>
      <ContentfulFormContext.Provider value={contentfulFormCtx}>
        <OctocaptchaContext.Provider value={octocaptchaCtx}>
          <ConsentExperienceContext.Provider value={consentExperienceCtx}>
            <ThemeProvider dir="ltr">{props.children}</ThemeProvider>
          </ConsentExperienceContext.Provider>
        </OctocaptchaContext.Provider>
      </ContentfulFormContext.Provider>
    </ErrorBoundary>
  )
}
