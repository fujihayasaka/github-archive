import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {LinkSchema} from './link'

export const LinkGroupSchema = buildEntrySchemaFor('linkGroup', {
  fields: z.object({
    heading: LinkSchema,
    links: z.array(LinkSchema).optional(),
  }),
})

export type LinkGroup = z.infer<typeof LinkGroupSchema>
