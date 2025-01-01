import {FormControl, TextInput} from '@primer/react-brand'
import {useContext} from 'react'
import {z} from 'zod'

import type {FormFieldTextInput} from '../../../../schemas/contentful/contentTypes/formFieldTextInput'
import {FormContext} from '../../../forms/Form/FormContext'
import {getValidation} from '../validations'
import parsePhoneNumberFromString from 'libphonenumber-js'

const CUSTOM_VALIDATIONS_BY_TYPE = {
  email: {
    message: 'Please enter a valid email address.',

    schema: z.string().trim().email(),
  },
  tel: {
    message: 'Please enter a valid phone number.',

    schema: z
      .string()
      .trim()
      .refine(value => {
        const phoneNumber = parsePhoneNumberFromString(value, {extract: false})
        return phoneNumber !== undefined && phoneNumber.isPossible()
      }),
  },
  text: {
    message: 'Please enter a value.',

    schema: z.string().trim(),
  },
} as const

export type ContentfulTextInputProps = {
  component: FormFieldTextInput
}

export function ContentfulTextInput({component: textInput}: ContentfulTextInputProps) {
  const formContext = useContext(FormContext)

  if (formContext === undefined) {
    throw new Error('ERROR: form context is undefined for ContentfulTextInput')
  }

  const required = textInput.fields.validations?.some(validation => validation.fields.name === 'REQUIRED') ?? false

  const validations = [
    CUSTOM_VALIDATIONS_BY_TYPE[textInput.fields.type],

    // additional validations from Contentful
    ...(textInput.fields.validations?.map(getValidation) ?? []),
  ]

  const error = formContext.errors[textInput.fields.htmlName]

  const validationErrorId = `${textInput.fields.htmlName}-validation-msg`

  const {id, ...registerProps} = formContext.register(textInput.fields.htmlName, {
    label: textInput.fields.label,
    required,
    validations,
  })

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
        aria-describedby={validationErrorId}
        placeholder={textInput.fields.placeholder}
        type={textInput.fields.type}
      />

      {typeof error === 'string' ? (
        <FormControl.Validation id={validationErrorId}>{error}</FormControl.Validation>
      ) : null}
    </FormControl>
  )
}
