import {z} from 'zod'
import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {RichTextSchema} from '@github-ui/swp-core/schemas/contentful/richText'

export const TemplateWhitepaperIndexSchema = buildEntrySchemaFor('templateWhitepaperIndex', {
  fields: z.object({
    excerpt: RichTextSchema,
  }),
})

export type WhitepaperIndex = z.infer<typeof TemplateWhitepaperIndexSchema>
