import {z} from 'zod'
import {buildEntrySchemaFor} from '../entry'
import {PrimerComponentStatisticSchema} from './primerComponentStatistic'

export const PrimerStatisticsSchema = buildEntrySchemaFor('primerStatistics', {
  fields: z.object({
    statistics: z.array(PrimerComponentStatisticSchema),
  }),
})

export type PrimerStatistics = z.infer<typeof PrimerStatisticsSchema>
