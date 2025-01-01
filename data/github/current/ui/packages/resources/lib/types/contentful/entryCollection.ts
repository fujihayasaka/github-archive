// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {z} from 'zod/v4'

/**
 * This is a very basic schema to ensure the resolveResponse function from
 * the 'contentful-resolve-response' package returns an collection of objects
 * that somewhat resembles the shape of a Contentful entry.
 */
export const EntryCollection = z.array(z.looseObject({})).min(1)

export type EntryCollection = z.infer<typeof EntryCollection>

export function toEntryCollection(collection: unknown): EntryCollection {
  return EntryCollection.parse(collection)
}
