import {z} from 'zod'
import {buildEntrySchemaFor} from '../entry'

export const PrimerComponentBreadcrumbSchema = buildEntrySchemaFor('primerComponentBreadcrumb', {
  fields: z.object({
    pageName: z.string(),
    path: z.string(),
    selected: z.boolean(),
  }),
})

export type PrimerComponentBreadcrumb = z.infer<typeof PrimerComponentBreadcrumbSchema>
