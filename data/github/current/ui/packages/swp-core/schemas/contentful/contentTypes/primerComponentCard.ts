import {z} from 'zod'
import {buildEntrySchemaFor} from '../entry'
import {AssetSchema} from '../../../../swp-core/schemas/contentful/contentTypes/asset'
import {RichTextSchema} from '../richText'
import {CardIconColors} from '@primer/react-brand'
import {PrimerComponentLabelSchema} from './primerComponentLabel'

export const PrimerComponentCardSchema = buildEntrySchemaFor('primerComponentCard', {
  fields: z.object({
    href: z.string(),
    label: z.union([z.string(), PrimerComponentLabelSchema]).optional(),
    heading: z.string(),
    description: RichTextSchema.optional(),
    ctaText: z.string().optional(),
    icon: z.string().optional(),
    iconColor: z.enum(CardIconColors).optional(),
    iconBackground: z.boolean().optional(),
    variant: z.enum(['default', 'minimal']).optional(),
    image: AssetSchema.optional(),
    hasBorder: z.boolean().optional(),
  }),
})

export type PrimerComponentCard = z.infer<typeof PrimerComponentCardSchema>
