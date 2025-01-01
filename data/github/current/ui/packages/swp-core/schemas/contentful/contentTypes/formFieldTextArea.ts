import {z} from 'zod/v4'

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

type FormFieldTextArea = z.infer<typeof FormFieldTextAreaSchema>

export const isFormFieldTextArea = (value: unknown): value is FormFieldTextArea => {
  return FormFieldTextAreaSchema.safeParse(value).success
}
