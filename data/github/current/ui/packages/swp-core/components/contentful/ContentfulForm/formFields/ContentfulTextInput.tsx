import {FormControl, TextInput} from '@primer/react-brand'
import {useContext} from 'react'

import type {FormFieldTextInput} from '../../../../schemas/contentful/contentTypes/formFieldTextInput'
import {FormContext} from '../../../forms/Form/FormContext'
import {ContentfulValidations, getValidation} from '../validations'
import {getAnalyticsEvent} from '../../../../lib/utils/analytics'
import {getHtmlTypeForTextInput} from './utils'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {PhoneInput} from './PhoneInput'
import {ConsentExperienceContext} from '../../../forms/Form/components/ConsentExperience/ConsentExperienceContext'

export type ContentfulTextInputProps = {
  component: FormFieldTextInput
}

export function ContentfulTextInput({component: textInput}: ContentfulTextInputProps) {
  const formContext = useContext(FormContext)
  const isPhoneFieldFormattingEnabled = isFeatureEnabled('contentful_lp_form_phone_e164')
  const consentExperienceCtx = useContext(ConsentExperienceContext)

  if (formContext === undefined) {
    throw new Error('ERROR: form context is undefined for ContentfulTextInput')
  }

  const required = textInput.fields.validations?.some(validation => validation.fields.name === 'REQUIRED') ?? false

  const validations =
    textInput.fields.validations?.map(validation => {
      // TODO: this is temporary until we can remove the old PHONE validation
      if (validation.fields.name === 'PHONE' && isPhoneFieldFormattingEnabled) {
        return ContentfulValidations.PHONE_E164
      }

      return getValidation(validation)
    }) ?? []

  const error = formContext.errors[textInput.fields.htmlName]

  const validationErrorId = `${textInput.fields.htmlName}-validation-msg`

  const {id, ...registerProps} = formContext.register(textInput.fields.htmlName, {
    label: textInput.fields.label,
    required,
    validations,
  })

  if (getHtmlTypeForTextInput(textInput) === 'tel' && isPhoneFieldFormattingEnabled) {
    return (
      <PhoneInput
        id={id}
        onChange={registerProps.onChange}
        error={error}
        required={required}
        placeholder={textInput.fields.placeholder}
        validationErrorId={validationErrorId}
        label={textInput.fields.label}
        name={registerProps.name}
        allowedCountries={
          consentExperienceCtx.marketingTargetedCountries?.length
            ? consentExperienceCtx.marketingTargetedCountries
            : undefined
        }
      />
    )
  }

  return (
    <FormControl
      key={textInput.fields.htmlName}
      id={id}
      fullWidth
      required={required}
      validationStatus={typeof error === 'string' ? 'error' : undefined}
    >
      <FormControl.Label>{textInput.fields.label}</FormControl.Label>

      <TextInput
        {...registerProps}
        {...getAnalyticsEvent({
          action: textInput.fields.label,
          tag: 'input',
          context: 'form_control',
          location: 'form',
        })}
        aria-describedby={validationErrorId}
        placeholder={textInput.fields.placeholder}
        type={getHtmlTypeForTextInput(textInput)}
      />

      {typeof error === 'string' ? (
        <FormControl.Validation id={validationErrorId}>{error}</FormControl.Validation>
      ) : null}
    </FormControl>
  )
}
