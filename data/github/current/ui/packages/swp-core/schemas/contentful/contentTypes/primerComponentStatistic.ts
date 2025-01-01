import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {RichTextSchema} from '../richText'

export const PrimerComponentStatisticSchema = buildEntrySchemaFor('primerComponentStatistic', {
  fields: z.object({
    heading: z.union([z.string(), RichTextSchema]),
    headingLevel: z.enum(['h2', 'h3', 'h4', 'h5', 'h6']).optional(),
    size: z.enum(['small', 'medium', 'large']),
    variant: z.enum(['boxed', 'default']).optional(),
    description: z.union([z.string(), RichTextSchema]).optional(),
    descriptionVariant: z.enum(['default', 'muted', 'accent']),
  }),
})

export type PrimerComponentStatistic = z.infer<typeof PrimerComponentStatisticSchema>
