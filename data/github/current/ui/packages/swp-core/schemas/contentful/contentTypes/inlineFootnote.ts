import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {RichTextSchema} from '../richText'

export const InlineFootnoteSchema = buildEntrySchemaFor('inlineFootnote', {
  fields: z.object({
    anchorId: z.string(),
    text: RichTextSchema,
  }),
})

export type InlineFootnote = z.infer<typeof InlineFootnoteSchema>
