import {z} from 'zod/v4'

import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {LinkSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/link'

export const GenericCTAGroupSchema = buildEntrySchemaFor('genericCtaGroup', {
  fields: z.object({
    primary: LinkSchema,
    secondary: LinkSchema.optional(),
    condition: z.string(),
  }),
})

export type GenericCTAGroup = z.infer<typeof GenericCTAGroupSchema>
