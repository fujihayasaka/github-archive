import type {z} from 'zod/v4'

import {buildPageSchemaForTemplate} from '@github-ui/swp-core/schemas/contentful/contentTypes/containerPage'

import {toEntryCollection} from '../../../../../lib/types/contentful/entryCollection'

import {TemplateBrandSchema} from './template-brand'
import type {BrandContentSchemaType} from './template-brand'

import {GENERIC_CONTENT} from './generic-content'
import type {GenericContent} from './generic-content'

import {GENERIC_GROUP} from './generic-group'
import type {GenericGroup} from './generic-group'

import type {GenericSection, GenericSectionContentSchemaType} from './generic-section'

const BrandPageSchema = buildPageSchemaForTemplate(TemplateBrandSchema)

export type BrandPage = z.infer<typeof BrandPageSchema>

interface BrandPageWithIds extends BrandPage {
  ids: {
    [key: string]: GenericContent | GenericGroup | GenericSection
  }
}

export function toBrandPage(contentfulPayload: unknown): BrandPageWithIds {
  const page = toEntryCollection(contentfulPayload).at(0)
  const parsedPage = BrandPageSchema.parse(page)
  const pageWithIds = extractContentIds(parsedPage)
  return pageWithIds
}

export function isBrandPage(contentfulPayload: unknown): boolean {
  const page = toEntryCollection(contentfulPayload).at(0)
  return BrandPageSchema.safeParse(page).success
}

export function getBrandContentById({content, id}: {content: BrandContentSchemaType; id: string}) {
  return content.find(item => item.fields.id === id)
}

export function getSectionContentById({content, id}: {content: GenericSectionContentSchemaType; id: string}) {
  return content
    .filter((item): item is GenericContent | GenericGroup =>
      [GENERIC_CONTENT, GENERIC_GROUP].includes(item.sys.contentType.sys.id),
    )
    .find(item => item.fields.id === id)
}

type EntryItem = {
  fields: {
    id?: string
    [key: string]: unknown
  }
}

function entryArrayToObject(array: EntryItem[] | undefined) {
  if (!Array.isArray(array) || array === undefined) return {}

  return Object.fromEntries(array.filter(item => item.fields?.id != null).map(item => [item.fields.id, item]))
}

function extractContentIds(page: BrandPage): BrandPageWithIds {
  const templateContent = page.fields.template.fields.content

  const templateContentWithIds = templateContent.map(item => {
    return {
      ...item,
      ids: {
        ...entryArrayToObject(item.fields.content),
      },
    }
  })

  const pageWithIds = {
    ...page,
    ids: {
      ...entryArrayToObject(templateContentWithIds),
    },
  }

  return pageWithIds
}
