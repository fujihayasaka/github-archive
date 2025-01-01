import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'

export const LinkSchema = buildEntrySchemaFor('link', {
  fields: z.object({
    href: z.string(),
    text: z.string(),
    openInNewTab: z.boolean().optional(),
  }),
})

export type Link = z.infer<typeof LinkSchema>

export function isLink(entry: unknown): entry is Link {
  return LinkSchema.safeParse(entry).success
}
