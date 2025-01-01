import {z} from 'zod/v4'

import {buildEntrySchemaFor} from '../entry'
import {FormFieldTextInputSchema} from './formFieldTextInput'
import {FormFieldTextAreaSchema} from './formFieldTextArea'

export const FormLayoutSchema = buildEntrySchemaFor('formLayout', {
  fields: z.object({
    formFields: z.array(z.union([FormFieldTextInputSchema, FormFieldTextAreaSchema]).readonly()).readonly(),
  }),
})
