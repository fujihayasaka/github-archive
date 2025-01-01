import {z} from 'zod'
import {LabelColors} from '@primer/react-brand'

import {buildEntrySchemaFor} from '../entry'
import {AppStoreButtonSchema} from './appStoreButton'
import {AssetSchema} from './asset'
import {LinkSchema} from './link'
import {PrimerComponentLabelSchema} from './primerComponentLabel'

export const PrimerComponentHeroSchema = buildEntrySchemaFor('primerComponentHero', {
  fields: z.object({
    align: z.literal('start').or(z.literal('center')),
    label: z.union([z.string(), PrimerComponentLabelSchema]).optional(),
    labelColor: z.enum(LabelColors).optional(),
    heading: z.string(),
    headingSize: z.enum(['1', '2', '3', 'display']).optional(),
    image: AssetSchema.optional(),
    imagePosition: z.literal('Block').or(z.literal('Inline')).optional(),
    videoSrc: z.string().optional(),
    description: z.string().optional(),
    descriptionVariant: z.enum(['default', 'muted']).optional(),
    callToActionPrimary: LinkSchema.optional(),
    callToActionSecondary: LinkSchema.optional(),
    trailingComponent: z.array(AppStoreButtonSchema).optional(),
  }),
})

export type PrimerComponentHero = z.infer<typeof PrimerComponentHeroSchema>
