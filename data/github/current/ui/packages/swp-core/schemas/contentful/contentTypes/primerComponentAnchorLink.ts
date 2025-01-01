import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'

export const PrimerComponentAnchorLinkSchema = buildEntrySchemaFor('primerComponentAnchorLink', {
  fields: z.object({
    href: z.string(),
    text: z.string(),
    ariaLabel: z.string().optional(),
  }),
})

export type PrimerComponentAnchorLink = z.infer<typeof PrimerComponentAnchorLinkSchema>
