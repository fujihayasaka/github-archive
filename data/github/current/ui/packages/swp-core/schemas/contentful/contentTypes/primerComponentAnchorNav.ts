import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {PrimerComponentAnchorLinkSchema} from './primerComponentAnchorLink'
import {LinkSchema} from './link'

export const PrimerComponentAnchorNavSchema = buildEntrySchemaFor('primerComponentAnchorNav', {
  fields: z.object({
    links: z.array(PrimerComponentAnchorLinkSchema),
    action: LinkSchema.optional(),
  }),
})

export type PrimerComponentAnchorNav = z.infer<typeof PrimerComponentAnchorNavSchema>
