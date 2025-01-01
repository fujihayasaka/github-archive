import {z} from 'zod'

import {buildEntrySchemaFor} from '../entry'
import {RichTextSchema} from '../richText'
import {FormLayoutSchema} from './formLayout'
import {MarketoCampaignSchema} from './marketoCampaign'

export const FormSchema = buildEntrySchemaFor('form', {
  fields: z.object({
    heading: RichTextSchema.optional(),
    campaign: MarketoCampaignSchema,
    layout: FormLayoutSchema,
    submitText: z.string(),
  }),
})

export type Form = z.infer<typeof FormSchema>
