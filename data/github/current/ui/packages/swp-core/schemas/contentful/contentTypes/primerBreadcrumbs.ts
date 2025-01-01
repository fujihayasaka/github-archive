import {z} from 'zod'
import {buildEntrySchemaFor} from '../entry'
import {PrimerComponentBreadcrumbSchema} from './primerComponentBreadcrumb'

export const PrimerBreadcrumbsSchema = buildEntrySchemaFor('primerBreadcrumbs', {
  fields: z.object({
    breadcrumbs: z.array(PrimerComponentBreadcrumbSchema),
  }),
})

export type PrimerBreadcrumbs = z.infer<typeof PrimerBreadcrumbsSchema>
