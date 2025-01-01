import parsePhoneNumberFromString from 'libphonenumber-js'
import {z, type ZodType} from 'zod/v4'

import type {FormFieldValidation} from '../../../../schemas/contentful/contentTypes/formFieldValidation'
import regex from './regex'

type ValidationBody = {
  message: string
  schema: ZodType
}

type Validations = Record<FormFieldValidation['fields']['name'], ValidationBody>

const validations: Validations = {
  REQUIRED: {
    message: 'This field is required.',

    schema: z.string().trim().min(1),
  },

  WORK_EMAIL_ONLY: {
    message: 'Please enter a valid work email address.',

    schema: z.email().refine(email => !regex.EMAIL_PERSONAL_DOMAIN_REGEX.test(email), {
      message: 'The email is from a personal email provider.',
    }),
  },

  EMAIL: {
    message: 'Please enter a valid email address.',

    schema: z.email(),
  },

  PHONE: {
    message: "Please enter a valid phone number with country code (e.g., '+1' for US).",

    schema: z
      .string()
      .trim()
      .refine(value => {
        const phoneNumber = parsePhoneNumberFromString(value, {extract: false})
        return phoneNumber !== undefined && phoneNumber.isPossible()
      }),
  },
  //TODO PHONE_E164 to be removed once the phone input component is fully released
  PHONE_E164: {
    message: 'Please enter a valid phone number.',
    schema: z
      .string()
      .trim()
      .refine(value => {
        const phoneNumber = parsePhoneNumberFromString(value, {extract: false})
        return phoneNumber !== undefined && phoneNumber.isPossible()
      }),
  },
} as const

export {validations as ContentfulValidations}

export function getValidation(validation: FormFieldValidation): ValidationBody {
  return validations[validation.fields.name]
}
