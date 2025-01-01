import {z} from 'zod'

import {buildEntrySchemaFor} from '../entry'
import {FormFieldValidationSchema} from './formFieldValidation'

export const FormFieldTextInputSchema = buildEntrySchemaFor('formFieldTextInput', {
  fields: z.object({
    htmlName: z.string(),
    label: z.string(),
    placeholder: z.string().optional(),
    type: z.enum(['email', 'text', 'tel']),
    validations: z.array(FormFieldValidationSchema).optional(),
  }),
})

export type FormFieldTextInput = z.infer<typeof FormFieldTextInputSchema>

export const isFormFieldTextInput = (value: unknown): value is FormFieldTextInput => {
  return FormFieldTextInputSchema.safeParse(value).success
}
