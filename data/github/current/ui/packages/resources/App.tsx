import type React from 'react'
import {useMemo} from 'react'

import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {ContentfulFormContext} from '@github-ui/swp-core/components/contentful/ContentfulForm'
import {OctocaptchaContext} from '@github-ui/swp-core/components/forms/OctocaptchaContext'
import {ConsentExperienceContext} from '@github-ui/swp-core/components/forms/ConsentExperienceContext'

import type {Country} from '@github-ui/swp-core/components/forms/ConsentExperience/types'

/**
 * The App component is used to render content which should be present on _all_ routes within this app
 */
export function App(props: {children?: React.ReactNode}) {
  /**
   * The app payload may be null depending on how the application is initialized
   * on the Rails controller.
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
    () => ({marketingFormsApiHost: payload?.marketingFormsApiHost}),
    [payload?.marketingFormsApiHost],
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
            {props.children}
          </ConsentExperienceContext.Provider>
        </OctocaptchaContext.Provider>
      </ContentfulFormContext.Provider>
    </ErrorBoundary>
  )
}
