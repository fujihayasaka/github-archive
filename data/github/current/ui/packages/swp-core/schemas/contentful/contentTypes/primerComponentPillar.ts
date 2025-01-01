import {z} from 'zod/v4'
import {PillarIconColors} from '@primer/react-brand'

import {buildEntrySchemaFor} from '../entry'
import {RichTextSchema} from '../richText'
import {LinkSchema} from './link'
import {AssetSchema} from './asset'

export const PrimerComponentPillarSchema = buildEntrySchemaFor('primerComponentPillar', {
  fields: z.object({
    align: z.enum(['start', 'center']),
    icon: z.string().optional(),
    iconColor: z.enum(PillarIconColors).optional(),
    image: AssetSchema.optional(),
    heading: z.string(),
    headingLevel: z.enum(['h2', 'h3', 'h4', 'h5', 'h6']).optional(),
    description: RichTextSchema,
    link: LinkSchema.optional(),
    transparent: z.boolean().optional(),
  }),
})

export type PrimerComponentPillar = z.infer<typeof PrimerComponentPillarSchema>
