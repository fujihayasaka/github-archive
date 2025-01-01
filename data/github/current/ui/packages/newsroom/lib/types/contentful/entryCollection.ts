// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {z} from 'zod'
import {TemplateCategorySchema} from './contentTypes/templates'
import {TemplateArticleSchema} from '@github-ui/resources/types'

/**
 * This is a very basic schema to ensure the resolveResponse function from
 * the 'contentful-resolve-response' package returns an collection of objects
 * that somewhat resembles the shape of a Contentful entry.
 */
export const EntryCollection = z.array(z.object({}).passthrough()).min(1)

export type EntryCollection = z.infer<typeof EntryCollection>

export function toEntryCollection(collection: unknown): EntryCollection {
  return EntryCollection.parse(collection)
}

export const CategoryEntryCollection = z.array(z.union([TemplateCategorySchema, TemplateArticleSchema])).min(1)
export type CategoryEntryCollection = z.infer<typeof CategoryEntryCollection>
export function toCategoryEntryCollection(collection: unknown): CategoryEntryCollection {
  return CategoryEntryCollection.parse(collection)
}
