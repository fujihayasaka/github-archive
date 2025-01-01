import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {LinkSchema} from './link'
import {AssetSchema} from './asset'
import {CardIconColors} from '@primer/react-brand'
import {RichTextSchema} from '../richText'

export const FeaturedBentoSchema = buildEntrySchemaFor('featuredBento', {
  fields: z.object({
    title: z.string(),
    heading: RichTextSchema,
    headingLevel: z.enum(['h2', 'h3', 'h4', 'h5', 'h6']).optional(),
    link: LinkSchema,
    icon: z.string().optional(),
    iconColor: z.enum(CardIconColors).optional(),
    image: AssetSchema.optional(),
  }),
})

export type FeaturedBentoType = z.infer<typeof FeaturedBentoSchema>
