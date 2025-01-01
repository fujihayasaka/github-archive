import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {RichTextSchema} from '../richText'
import {AssetSchema} from './asset'
import {LinkSchema} from './link'

export const PrimerComponentRiverAccordionItemSchema = buildEntrySchemaFor('primerComponentRiverAccordionItem', {
  fields: z.object({
    heading: RichTextSchema,
    headingLevel: z.enum(['h2', 'h3', 'h4', 'h5', 'h6']).optional(),
    text: RichTextSchema,
    callToAction: LinkSchema.optional(),
    callToActionVariant: z.enum(['default', 'accent']).optional(),
    image: AssetSchema,
    imageAlt: z.string().optional(),
  }),
})

export type PrimerComponentRiverAccordionItem = z.infer<typeof PrimerComponentRiverAccordionItemSchema>
