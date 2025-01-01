// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {z} from 'zod'
import {buildPageSchemaForTemplate} from '@github-ui/swp-core/schemas/contentful/contentTypes/containerPage'
import {TemplateHomeSchema, TemplateCategorySchema} from './templates'
import {TemplateArticleSchema} from '@github-ui/resources/types'

const HomePageSchema = buildPageSchemaForTemplate(TemplateHomeSchema)
export type HomePageContainer = z.infer<typeof HomePageSchema>

export function toHomePage(item: unknown): HomePageContainer {
  return HomePageSchema.parse(item)
}

const CategoryPageSchema = buildPageSchemaForTemplate(TemplateCategorySchema)
export type CategoryPageContainer = z.infer<typeof CategoryPageSchema>

export function toCategoryPage(item: unknown): CategoryPageContainer {
  return CategoryPageSchema.parse(item)
}

const ContainerPageSchema = z.union([CategoryPageSchema, buildPageSchemaForTemplate(TemplateArticleSchema)])

export type ContainerPage = z.infer<typeof ContainerPageSchema>
export function toContainerPage(item: unknown): ContainerPage {
  return ContainerPageSchema.parse(item)
}
