import {useEffect, useState} from 'react'
import ConsentLanguage from './consent-language/ConsentLanguage'

export interface ConsentExperienceProps {
  fieldName: string
  countryFieldSelector: string
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
   * Explicitly list the exampleFields that will be shared upon consent, even for countries that don't require it.
   * This follows Privacy's guidance, when the checkbox is not directly situated next to the fields.
   * See https://github.com/github/privacy/issues/1367#issuecomment-2625374650.
   */
  listExampleFields?: boolean
  /**
   * Classes to be applied to the label around the form elements. Not applied to South Korea due to specific styling
   * requirements for that country.
   */
  labelClass?: string
  /**
   * Classes to be applied to the wrapper around the form elements
   */
  formControlClass?: string
  /**
   * Classes to be applied to the notice that appears below the form elements
   */
  noticeClass?: string
  /**
   * Optional callback that will be called if the consent experience changes their validation state.
   * Some countries require additional explicit consent for the privacy statement (e.g. South Korea).
   *
   * This is helpful to validate the form programmatically before submission from the parent component.
   */
  onValidationChange?: (isValid: boolean) => void
  /**
   * The value for the marketing consent field. Defaults to `1`.
   */
  fieldValue?: string
  /**
   * If true, the field will only be sent if the checkbox is checked. Defaults to `false`.
   */
  onlySendIfChecked?: boolean
  /**
   * Initial country code to provide a default value for the selected country.
   * This can be used if the consent doesn't include a country select, e.g. in the Copilot Pro flow.
   */
  initialCountry?: string
  /**
   * Classes to be applied to the emphasized text in the South Korea consent language. The emphasized text must be:
   * - At least 9-point font AND 20% larger than the rest of consent text, and
   * - In a different color, bold, or underlined.
   */
  emphasizedTextForKoreaClass?: string
}

export function ConsentExperience({
  countryFieldSelector,
  fieldName,
  fieldValue = '1',
  onlySendIfChecked = false,
  onValidationChange,
  initialCountry,
  ...passThruProps
}: ConsentExperienceProps) {
  const [country, setCountry] = useState(initialCountry ? initialCountry : '')
  const [consentChecked, setConsentChecked] = useState(false)

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
    const countryField = document.querySelector(countryFieldSelector) as HTMLSelectElement

    if (countryField) {
      const handleChange = (event: Event): void => {
        /**
         * Unless the new rendered ConsentLanguage component says otherwise, we assume
         * the consent experience is valid when the country changes.
         */
        if (onValidationChange) {
          onValidationChange(true)
        }

        setCountry((event.currentTarget as HTMLSelectElement).value)
        setConsentChecked(false)
      }

      countryField.addEventListener('change', handleChange)

      return () => {
        countryField.removeEventListener('change', handleChange)
      }
    }
  }, [onValidationChange, countryFieldSelector])

  return (
    <div data-testid="consent-experience">
      <ConsentLanguage
        fieldName={fieldName}
        country={country}
        onValidationChange={onValidationChange}
        {...passThruProps}
      >
        {!onlySendIfChecked && <input type="hidden" name={fieldName} value="0" data-testid="hidden-consent" />}

        <input
          type="checkbox"
          name={fieldName}
          value={fieldValue}
          id={fieldName}
          className="form-control"
          checked={consentChecked}
          onChange={() => setConsentChecked(!consentChecked)}
        />
      </ConsentLanguage>
    </div>
  )
}
