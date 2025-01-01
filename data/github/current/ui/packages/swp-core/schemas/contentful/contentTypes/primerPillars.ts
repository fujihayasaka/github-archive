import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {PrimerComponentPillarSchema} from './primerComponentPillar'

export const PrimerPillarsSchema = buildEntrySchemaFor('primerPillars', {
  fields: z.object({
    pillars: z.array(PrimerComponentPillarSchema),
  }),
})

export type PrimerPillars = z.infer<typeof PrimerPillarsSchema>
