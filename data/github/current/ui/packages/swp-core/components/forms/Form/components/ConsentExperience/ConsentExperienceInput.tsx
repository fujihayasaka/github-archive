import {useContext, useEffect, useState} from 'react'
import {Checkbox} from '@primer/react-brand'

import ConsentLanguage from './ConsentLanguage/ConsentLanguage'
import {ConsentValue} from './types'
import {FormContext} from '../../FormContext'
import {getAnalyticsEvent} from '../../../../../lib/utils/analytics'
import type {Country} from './types'
import {isFeatureEnabled} from '@github-ui/feature-flags'

const IMPLICIT_CONSENT_COUNTRIES = ['US']

export interface ConsentExperienceProps {
  fieldName: string
  selectedCountry: Country
  privacyStatementHref: string
  emailSubscriptionSettingsLinkHref: string
  hasPhone?: boolean
  /**
   * List of fields that will be used as examples in the consent language for South Korea. For example, if the form
   * contains a field for the user's first name, last name, and email address, you may pass
   * in `['first name', 'last name', 'email']`.
   */
  exampleFields: string[]
  /**
   * Optional callback that will be called if the consent experience changes their validation state.
   * Some countries require additional explicit consent for the privacy statement (e.g. South Korea).
   *
   * This is helpful to validate the form programmatically before submission from the parent component.
   */
  onValidationChange?: (isValid: boolean) => void
  /**
   * If true, the field will only be sent if the checkbox is checked. Defaults to `false`.
   */
  onlySendIfChecked?: boolean
}

export function ConsentExperienceInput({
  selectedCountry,
  fieldName,
  onValidationChange,
  ...passThruProps
}: ConsentExperienceProps) {
  const [consentChecked, setConsentChecked] = useState(false)
  const [showCheckbox, setShowCheckbox] = useState(true)
  const formContext = useContext(FormContext)

  const {
    onChange: marketingOptInOnChange,
    ref,
    ...registerMarketingEmailOptInProps
  } = formContext?.register(fieldName, {
    label: 'Marketing Email Opt In',
    required: false,
  }) ?? {}

  /**
   * Unless the underlying ConsentLanguage component says otherwise, we assume
   * the consent experience is valid by default.
   */
  useEffect(() => {
    if (onValidationChange) {
      onValidationChange(true)
    }
  }, [onValidationChange])

  useEffect(() => {
    if (!isFeatureEnabled('contact_requests_implicit_opt_in')) return

    if (IMPLICIT_CONSENT_COUNTRIES.includes(selectedCountry.alpha)) {
      setShowCheckbox(false)
    } else {
      setShowCheckbox(true)
    }
  }, [selectedCountry])

  return (
    <div data-testid="consent-experience">
      <ConsentLanguage
        fieldName={fieldName}
        country={selectedCountry.alpha}
        onValidationChange={onValidationChange}
        {...passThruProps}
      >
        {showCheckbox ? (
          <Checkbox
            value={ConsentValue.EXPLICIT}
            checked={consentChecked}
            hidden={!showCheckbox}
            onChange={event => {
              marketingOptInOnChange?.(event)
              setConsentChecked(!consentChecked)
            }}
            ref={ref}
            {...getAnalyticsEvent({
              action: 'consent_language',
              tag: 'checkbox',
              context: 'form_control',
              location: 'form',
            })}
            {...registerMarketingEmailOptInProps}
          />
        ) : (
          <input
            type="hidden"
            name={fieldName}
            value={ConsentValue.IMPLICIT}
            ref={ref as React.Ref<HTMLInputElement>}
          />
        )}
      </ConsentLanguage>
    </div>
  )
}
