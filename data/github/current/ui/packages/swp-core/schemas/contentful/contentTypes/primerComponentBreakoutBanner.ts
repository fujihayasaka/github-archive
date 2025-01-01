import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {LinkSchema} from './link'
import {AssetSchema} from './asset'
import {RichTextSchema} from '../richText'

export const PrimerComponentBreakoutBannerSchema = buildEntrySchemaFor('primerComponentBreakoutBanner', {
  fields: z.object({
    align: z.enum(['start', 'center']),
    backgroundColor: z.enum(['default', 'subtle']).optional(),
    backgroundImage: AssetSchema.optional(),
    ctaLink: LinkSchema,
    heading: RichTextSchema,
    headingLevel: z.enum(['h2', 'h3', 'h4', 'h5', 'h6']).optional(),
    logo: z.string().optional(),
  }),
})

export type PrimerComponentBreakoutBanner = z.infer<typeof PrimerComponentBreakoutBannerSchema>
