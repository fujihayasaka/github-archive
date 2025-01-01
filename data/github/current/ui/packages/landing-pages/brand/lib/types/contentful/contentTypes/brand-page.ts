import type {z} from 'zod'

import {buildPageSchemaForTemplate} from '@github-ui/swp-core/schemas/contentful/contentTypes/containerPage'

import {toEntryCollection} from '../../../../../lib/types/contentful/entryCollection'

import {TemplateBrandSchema} from './template-brand'
import type {BrandContentSchemaType} from './template-brand'

const BrandPageSchema = buildPageSchemaForTemplate(TemplateBrandSchema)
export type BrandPage = z.infer<typeof BrandPageSchema>

export function toBrandPage(contentfulPayload: unknown): BrandPage {
  const page = toEntryCollection(contentfulPayload).at(0)
  return BrandPageSchema.parse(page)
}

export function isBrandPage(contentfulPayload: unknown): boolean {
  const page = toEntryCollection(contentfulPayload).at(0)
  return BrandPageSchema.safeParse(page).success
}

export function getBrandContentById({content, id}: {content: BrandContentSchemaType; id: string}) {
  return content.find(item => item.fields.id === id)
}
