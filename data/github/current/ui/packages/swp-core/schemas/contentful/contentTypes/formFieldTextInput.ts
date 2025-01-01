import {z} from 'zod'

import {buildEntrySchemaFor} from '../entry'
import {FormFieldValidationSchema} from './formFieldValidation'

export const FormFieldTextInputSchema = buildEntrySchemaFor('formFieldTextInput', {
  fields: z.object({
    htmlName: z.string(),
    label: z.string(),
    placeholder: z.string().optional(),
    type: z.enum(['email']),
    validations: z.array(FormFieldValidationSchema).optional(),
  }),
})

export const isFormFieldTextInput = (value: unknown): value is z.infer<typeof FormFieldTextInputSchema> => {
  return FormFieldTextInputSchema.safeParse(value).success
}
