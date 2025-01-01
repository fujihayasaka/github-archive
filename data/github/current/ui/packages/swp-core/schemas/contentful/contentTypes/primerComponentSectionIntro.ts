import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {RichTextSchema} from '../richText'
import {LinkSchema} from './link'
import {PrimerComponentLabelSchema} from './primerComponentLabel'
import {AssetSchema} from './asset'

export const PrimerComponentSectionIntroSchema = buildEntrySchemaFor('primerComponentSectionIntro', {
  fields: z.object({
    align: z.literal('start').or(z.literal('center')),
    leadingComponent: AssetSchema.optional(),
    leadingComponentSize: z.enum(['small', 'large']).optional(),
    label: PrimerComponentLabelSchema.optional(),
    description: RichTextSchema.optional(),
    fullWidth: z.boolean().optional(),
    heading: RichTextSchema,
    link: LinkSchema.optional(),
    linkVariant: z.enum(['default', 'accent']).optional(),
    htmlId: z.string().optional(),
  }),
})

export type PrimerComponentSectionIntro = z.infer<typeof PrimerComponentSectionIntroSchema>
