import {z} from 'zod/v4'

import {AssetSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/asset'
import {FormSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/form'
import {PrimerComponentCardSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentCard'
import {PrimerComponentProseSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentProse'
import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {RichTextSchema} from '@github-ui/swp-core/schemas/contentful/richText'

// smaller version to support caching in BE
// see https://github.com/github/marketing-platform-services/issues/3261
export const TemplateWhitepaperTruncatedSchema = buildEntrySchemaFor('templateWhitepaper', {
  fields: z.object({
    heading: z.string(),
    contentType: z.string(),
    featuredImage: AssetSchema.optional(),
    excerpt: RichTextSchema,
  }),
})

export type WhitepaperTruncated = z.infer<typeof TemplateWhitepaperTruncatedSchema>

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
    form: FormSchema,
    downloadableAsset: AssetSchema.optional(),
    downloadableAssetUrl: z.string().optional(),
    downloadableAssetCta: z.string().optional(),
    confirmationCtaDescription: z.string().optional(),
    relatedResources: z.array(PrimerComponentCardSchema).optional(),
    topics: z.array(z.string()).optional(),
  }),
})

export type WhitepaperPage = z.infer<typeof TemplateWhitepaperSchema>
