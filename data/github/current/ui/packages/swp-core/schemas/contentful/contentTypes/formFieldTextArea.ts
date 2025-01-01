import {z} from 'zod'

import {buildEntrySchemaFor} from '../entry'
import {FormFieldValidationSchema} from './formFieldValidation'

export const FormFieldTextAreaSchema = buildEntrySchemaFor('formFieldTextArea', {
  fields: z.object({
    htmlName: z.string(),
    label: z.string(),
    placeholder: z.string().optional(),
    validations: z.array(FormFieldValidationSchema).optional(),
  }),
})

export const isFormFieldTextArea = (value: unknown): value is z.infer<typeof FormFieldTextAreaSchema> => {
  return FormFieldTextAreaSchema.safeParse(value).success
}
