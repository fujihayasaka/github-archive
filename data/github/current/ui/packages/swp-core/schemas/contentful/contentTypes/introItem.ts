import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {RichTextSchema} from '../richText'

export const IntroItemSchema = buildEntrySchemaFor('introItem', {
  fields: z.object({
    text: RichTextSchema,
  }),
})

export type IntroItem = z.infer<typeof IntroItemSchema>
