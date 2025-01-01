import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {RichTextSchema} from '../richText'
import {LinkSchema} from './link'
import {AppStoreButtonSchema} from './appStoreButton'
import {BackgroundImageSchema} from './backgroundImage'

export const PrimerComponentCtaBannerSchema = buildEntrySchemaFor('primerComponentCtaBanner', {
  fields: z.object({
    align: z.enum(['start', 'center']),
    heading: z.string(),
    headingLevel: z.enum(['h2', 'h3', 'h4', 'h5', 'h6']).optional(),
    headingSize: z.enum(['2', '3', '4', '5', '6']).optional(),
    description: RichTextSchema.optional(),
    hasBorder: z.boolean().optional(),
    hasShadow: z.boolean().optional(),
    backgroundImage: BackgroundImageSchema.optional(),
    hasBackground: z.boolean().optional(),
    callToActionPrimary: LinkSchema,
    callToActionPrimaryVariant: z.enum(['primary', 'accent']).optional(),
    callToActionSecondary: LinkSchema.optional(),
    trailingComponent: z.array(AppStoreButtonSchema).optional(),
  }),
})

export type PrimerComponentCtaBanner = z.infer<typeof PrimerComponentCtaBannerSchema>
