import {z} from 'zod'
import {buildPageSchemaForTemplate} from '@github-ui/swp-core/schemas/contentful/contentTypes/containerPage'
import {TemplateArticleSchema, TemplateArticleTruncatedSchema} from './templateResourcesArticle'
import {TemplateWhitepaperIndexSchema} from './templateWhitepaperIndex'
import {TemplateWhitepaperSchema, TemplateWhitepaperTruncatedSchema} from './templateWhitepaper'

const ArticlePageSchema = buildPageSchemaForTemplate(TemplateArticleSchema)
const CategoryPageSchema = buildPageSchemaForTemplate(TemplateArticleTruncatedSchema)
const WhitepaperPageSchema = buildPageSchemaForTemplate(TemplateWhitepaperSchema)

const WhitepaperIndexSchema = buildPageSchemaForTemplate(TemplateWhitepaperIndexSchema)
const WhitepaperTruncatedSchema = buildPageSchemaForTemplate(TemplateWhitepaperTruncatedSchema)

export type ArticlePageContainer = z.infer<typeof ArticlePageSchema>
export type CategoryPageContainer = z.infer<typeof CategoryPageSchema>
export type WhitepaperPageContainer = z.infer<typeof WhitepaperPageSchema>

export function toArticlePage(item: unknown): ArticlePageContainer {
  return ArticlePageSchema.parse(item)
}

export function toCategoryPage(items: unknown[]): CategoryPageContainer[] {
  return items.map(item => CategoryPageSchema.parse(item))
}

export type WhitepaperIndexContainer = z.infer<typeof WhitepaperIndexSchema>
export type WhitepaperDetailTruncatedContainer = z.infer<typeof WhitepaperTruncatedSchema>

export function toWhitepaperIndex(item: unknown): WhitepaperIndexContainer {
  return WhitepaperIndexSchema.parse(item)
}

export function toTruncatedWhitepaper(item: unknown): WhitepaperDetailTruncatedContainer {
  return WhitepaperTruncatedSchema.parse(item)
}

const WhitepaperContainerPageSchema = z.union([WhitepaperIndexSchema, WhitepaperTruncatedSchema])

export type WhitepaperContainerPage = z.infer<typeof WhitepaperContainerPageSchema>
export function toWhitepaperContainerPage(item: unknown): WhitepaperContainerPage {
  return WhitepaperContainerPageSchema.parse(item)
}

export function toWhitepaperPage(item: unknown): WhitepaperPageContainer {
  return WhitepaperPageSchema.parse(item)
}
