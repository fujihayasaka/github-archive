import {z} from 'zod/v4'

import {buildEntrySchemaFor} from '../entry'

export const FormFieldValidationSchema = buildEntrySchemaFor('formFieldValidation', {
  //TODO PHONE_E164 to be removed once the phone input component is fully released
  fields: z.object({
    name: z.enum(['REQUIRED', 'WORK_EMAIL_ONLY', 'EMAIL', 'PHONE', 'PHONE_E164']),
  }),
})

export type FormFieldValidation = z.infer<typeof FormFieldValidationSchema>
