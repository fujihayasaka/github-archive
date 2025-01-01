import {z} from 'zod'

import {buildEntrySchemaFor} from '../entry'

export const FormFieldValidationSchema = buildEntrySchemaFor('formFieldValidation', {
  fields: z.object({
    name: z.enum(['REQUIRED', 'WORK_EMAIL_ONLY']),
  }),
})

export type FormFieldValidation = z.infer<typeof FormFieldValidationSchema>
