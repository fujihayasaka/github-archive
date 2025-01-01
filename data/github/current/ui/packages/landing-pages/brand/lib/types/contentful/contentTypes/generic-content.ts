import {z} from 'zod'

import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {RichTextSchema} from '@github-ui/swp-core/schemas/contentful/richText'
import {LinkSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/link'
import {PrimerComponentLabelSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentLabel'

import {GenericAssetSchema} from './generic-asset'

export const GenericContentSchema = buildEntrySchemaFor('genericContent', {
  fields: z.object({
    id: z.string().optional(),
    htmlId: z.string().optional(),
    label: PrimerComponentLabelSchema.optional(),
    heading: z.string().optional(),
    subheading: RichTextSchema.optional(),
    text: RichTextSchema.optional(),
    links: z.array(LinkSchema).max(2).optional(),
    media: z.array(GenericAssetSchema).optional(),
    content: z.array(z.any()).optional(),
  }),
})

export type GenericContent = z.infer<typeof GenericContentSchema>
