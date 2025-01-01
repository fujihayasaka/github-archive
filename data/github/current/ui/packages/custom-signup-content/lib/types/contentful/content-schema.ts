import {z} from 'zod/v4'

import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {RichTextSchema} from '@github-ui/swp-core/schemas/contentful/richText'

export const ContentSchema = buildEntrySchemaFor('content', {
  fields: z.object({
    id: z.string(),
    htmlId: z.string(),
    title: z.string(),
    heading: z.string(),
    text: RichTextSchema,
  }),
})

export type ContentSchema = z.infer<typeof ContentSchema>
