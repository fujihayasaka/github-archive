import {z} from 'zod'
import {RichTextSchema} from '@github-ui/swp-core/schemas/contentful/richText'
import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {buildPageSchemaForTemplate} from '@github-ui/swp-core/schemas/contentful/contentTypes/containerPage'
import {AssetSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/asset'
import {PrimerComponentProseSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentProse'

// smaller version to support caching in BE
// see https://github.com/github/marketing-platform-services/issues/3261
export const TemplateWhitepaperTruncatedSchema = buildEntrySchemaFor('templateWhitepaper', {
  fields: z.object({
    heading: z.string(),
    contentType: z.string(),
    featuredImage: AssetSchema,
    excerpt: RichTextSchema,
  }),
})

export type WhitepaperTruncated = z.infer<typeof TemplateWhitepaperTruncatedSchema>

const ResourcePages = buildPageSchemaForTemplate(z.object({}))

export const TemplateWhitepaperSchema = buildEntrySchemaFor('templateWhitepaper', {
  fields: z.object({
    title: z.string(),
    contentType: z.union([z.literal('Whitepaper'), z.literal('Ebook')]),
    heading: z.string(),
    publishedDate: z.string().optional(),
    featuredImage: AssetSchema.optional(),
    lede: RichTextSchema,
    excerpt: RichTextSchema,
    body: PrimerComponentProseSchema,
    form: z.object({}),
    relatedResources: z.array(ResourcePages).optional(),
  }),
})

export type WhitepaperPage = z.infer<typeof TemplateWhitepaperSchema>
