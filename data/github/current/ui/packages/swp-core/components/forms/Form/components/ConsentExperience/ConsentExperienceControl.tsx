import {useContext} from 'react'
import {FormControl, Stack} from '@primer/react-brand'
import {ConsentExperience} from './ConsentExperience'

import {FormContext} from '../../FormContext'
import {CountrySelectField} from './CountrySelect/CountrySelectField'
import {ConsentExperienceContext} from './ConsentExperienceContext'

export const ConsentExperienceControl = () => {
  const consentExperienceExamplesFields = ['first name', 'last name', 'company', 'email']
  const formContext = useContext(FormContext)
  const ctx = useContext(ConsentExperienceContext)

  const primaryConsentError = formContext?.errors['primaryConsent']
  const primaryConsentId = formContext?.formFields?.['primaryConsent']?.id

  return (
    <Stack direction="vertical" gap="condensed" padding="none">
      <CountrySelectField countries={ctx.marketingTargetedCountries || []} />

      <FormControl
        id="form-field-consent-experience"
        validationStatus={typeof primaryConsentError === 'string' ? 'error' : undefined}
        fullWidth
      >
        <ConsentExperience
          countryFieldSelector="#form-field-country"
          emailSubscriptionSettingsLinkHref="/settings/emails/subscriptions/link-request/new"
          exampleFields={consentExperienceExamplesFields}
          fieldName="marketing_email_opt_in"
          fieldValue="optInExplicit"
          onlySendIfChecked
          privacyStatementHref="https://docs.github.com/articles/github-privacy-statement"
        />

        {typeof primaryConsentError === 'string' ? (
          <FormControl.Validation id={`${primaryConsentId}-validation`}>{primaryConsentError}</FormControl.Validation>
        ) : null}
      </FormControl>
    </Stack>
  )
}
