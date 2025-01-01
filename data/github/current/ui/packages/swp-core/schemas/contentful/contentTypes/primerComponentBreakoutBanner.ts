import {z} from 'zod'
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
    logo: z.string().optional(),
  }),
})

export type PrimerComponentBreakoutBanner = z.infer<typeof PrimerComponentBreakoutBannerSchema>
