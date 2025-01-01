import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {RichTextSchema} from '../richText'

export const PrimerComponentStaticFootnotesSchema = buildEntrySchemaFor('primerComponentStaticFootnotes', {
  fields: z.object({
    content: RichTextSchema,
    visuallyHiddenHeading: z.string().optional(),
  }),
})

export type PrimerComponentStaticFootnotes = z.infer<typeof PrimerComponentStaticFootnotesSchema>
