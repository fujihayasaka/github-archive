import {useContext, useState} from 'react'
import {FormControl, Stack} from '@primer/react-brand'
import {ConsentExperienceInput} from './ConsentExperienceInput'

import {FormContext} from '../../FormContext'
import {CountrySelectField} from './CountrySelect/CountrySelectField'
import {ConsentExperienceContext} from './ConsentExperienceContext'
import type {Country} from './types'

export const ConsentExperience = () => {
  const consentExperienceExamplesFields = ['first name', 'last name', 'company', 'email']
  const formContext = useContext(FormContext)
  const ctx = useContext(ConsentExperienceContext)

  const primaryConsentError = formContext?.errors['primaryConsent']
  const primaryConsentId = formContext?.formFields?.['primaryConsent']?.id

  const [selectedCountry, setSelectedCountry] = useState<Country>({name: '', alpha: ''})

  return (
    <Stack direction="vertical" gap="condensed" padding="none">
      <CountrySelectField
        countries={ctx.marketingTargetedCountries || []}
        onChange={country => setSelectedCountry(country)}
      />

      <FormControl
        id="form-field-consent-experience"
        validationStatus={typeof primaryConsentError === 'string' ? 'error' : undefined}
        fullWidth
      >
        <ConsentExperienceInput
          selectedCountry={selectedCountry}
          emailSubscriptionSettingsLinkHref="/settings/emails/subscriptions/link-request/new"
          exampleFields={consentExperienceExamplesFields}
          fieldName="marketing_email_opt_in"
          privacyStatementHref="https://docs.github.com/articles/github-privacy-statement"
        />

        {typeof primaryConsentError === 'string' ? (
          <FormControl.Validation id={`${primaryConsentId}-validation`}>{primaryConsentError}</FormControl.Validation>
        ) : null}
      </FormControl>
    </Stack>
  )
}
