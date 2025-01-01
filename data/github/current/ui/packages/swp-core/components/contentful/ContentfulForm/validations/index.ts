import {z, type ZodTypeAny} from 'zod'

import type {FormFieldValidation} from '../../../../schemas/contentful/contentTypes/formFieldValidation'
import regex from './regex'

type ValidationBody = {
  message: string
  schema: ZodTypeAny
}

type Validations = Record<FormFieldValidation['fields']['name'], ValidationBody>

const validations: Validations = {
  REQUIRED: {
    message: 'This field is required.',

    schema: z.string().trim().min(1),
  },

  WORK_EMAIL_ONLY: {
    message: 'Please enter a valid work email address.',

    schema: z
      .string()
      .email()
      .refine(email => !regex.EMAIL_PERSONAL_DOMAIN_REGEX.test(email), {
        message: 'The email is from a personal email provider.',
      }),
  },
} as const

export function getValidation(validation: FormFieldValidation): ValidationBody {
  return validations[validation.fields.name]
}
